import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'price_change_service.dart';

/// Gemini Flash ile A4 fiyat degisim tablosunu yapilandirilmis JSON'a cevirir.
/// API anahtari cihazda sifreli saklanir (flutter_secure_storage).
/// Anahtar yoksa/istek basarisizsa cagiran ML Kit fallback'ine doner.
class GeminiOcrService {
  GeminiOcrService._();
  static final GeminiOcrService instance = GeminiOcrService._();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'gemini_api_key';
  static const _model = 'gemini-2.0-flash';

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<void> setApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());
  Future<void> clearApiKey() => _storage.delete(key: _keyName);
  Future<bool> hasApiKey() async {
    final k = await getApiKey();
    return k != null && k.isNotEmpty;
  }

  /// A4 fotografini Gemini'ye gonderir, tablo satirlarini dondurur.
  /// Hata durumunda GeminiOcrException firlatir (cagiran fallback yapar).
  Future<List<PriceChangeItem>> extractTable(
      File image, int sessionId) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('API anahtarı yok');
    }

    final bytes = await image.readAsBytes();
    final b64 = base64Encode(bytes);

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$key');

    const prompt = '''
Bu görüntü bir market fiyat değişim tablosudur. Sütunlar: Barkod, Stok Adı, Stok Kodu, Fiyatı (yeni), Eski Fiyatı, Reyonu.
Tablodaki HER satırı oku ve SADECE şu formatta bir JSON dizisi döndür (başka hiçbir metin yazma):
[{"barcode":"8690632994055","name":"NESTLE DAMAK 60GR FISTIKLI KARE","newPrice":76.95,"oldPrice":44.5,"aisle":"ANPA - ATISTIRMALIK"}]
Kurallar:
- barcode: 12-13 haneli sayı (Stok Kodu DEĞİL, soldaki uzun barkod).
- newPrice = "Fiyatı" sütunu, oldPrice = "Eski Fiyatı" sütunu. Virgülü noktaya çevir.
- name: yıldız (*) karakterlerini temizle.
- Okunamayan alanı null yap, satırı atlama.
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'responseMimeType': 'application/json',
      },
    });

    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 45));

    if (res.statusCode != 200) {
      throw GeminiOcrException(
          'Gemini hatası (${res.statusCode}): ${_shortError(res.body)}');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
        as String?;
    if (text == null || text.trim().isEmpty) {
      throw const GeminiOcrException('Gemini boş yanıt döndü');
    }

    // JSON'i ayikla (bazen ```json bloklari gelir).
    final cleaned = text
        .replaceAll(RegExp(r'^```json', multiLine: true), '')
        .replaceAll(RegExp(r'^```', multiLine: true), '')
        .trim();

    final List<dynamic> rows;
    try {
      rows = jsonDecode(cleaned) as List<dynamic>;
    } catch (_) {
      throw const GeminiOcrException('Gemini yanıtı çözümlenemedi');
    }

    final now = DateTime.now();
    final items = <PriceChangeItem>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final barcode = (row['barcode']?.toString() ?? '').trim();
      if (barcode.length < 12 || barcode.length > 13) continue;
      if (!RegExp(r'^\d+$').hasMatch(barcode)) continue;
      if (seen.contains(barcode)) continue;
      seen.add(barcode);

      items.add(PriceChangeItem(
        batchId: 'gemini',
        sessionId: sessionId,
        barcode: barcode,
        productName: _str(row['name']),
        newPrice: _num(row['newPrice']),
        oldPrice: _num(row['oldPrice']),
        aisle: _str(row['aisle']),
        createdAt: now,
      ));
    }
    if (items.isEmpty) {
      throw const GeminiOcrException('Tabloda satır bulunamadı');
    }
    return items;
  }

  /// SON KULLANMA TARIHI (SKT) OKUMA.
  /// Urun ambalajindan/etiketinden cekilen fotografi Gemini'ye gonderir,
  /// gordugu son kullanma tarihini dondurur. Bulamazsa/hata olursa
  /// GeminiOcrException firlatir (cagiran elle girise yonlendirir).
  ///
  /// Donen deger: gun bazinda DateTime (saat 00:00). Sadece ay/yil
  /// goruldyse o ayin SON gununu alir (ornek: "03/2025" -> 31.03.2025),
  /// cunku gida urunlerinde "ay sonu" guvenli kabuldur.
  Future<DateTime> extractExpiryDate(File image) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('API anahtarı yok');
    }

    final bytes = await image.readAsBytes();
    final b64 = base64Encode(bytes);

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$key');

    final today = DateTime.now();
    final prompt = '''
Bu fotoğraf bir gıda/market ürününün ambalajı veya etiketidir. Üzerinde son kullanma tarihi (SKT / SON KUL. TAR. / TETT / EXP / best before) yazıyor olabilir.
Görüntüdeki SON KULLANMA tarihini bul ve SADECE şu formatta tek satır JSON döndür (başka hiçbir şey yazma):
{"day":31,"month":3,"year":2025,"found":true}
Kurallar:
- found: tarih net okunduysa true, okunamadıysa veya hiç tarih yoksa false.
- Sadece GÜN/AY varsa year'ı en mantıklı yıla tamamla (bugün ${today.year}). Sadece AY/YIL varsa day'i null bırak.
- Üretim tarihi (ÜRT / imal) ile karıştırma; SON KULLANMA olanı seç. İkisi varsa ileri tarihli olan SKT'dir.
- Tarih formatı gün.ay.yıl veya yıl-ay-gün olabilir; doğru ayır.
- found false ise day/month/year null olabilir.
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'responseMimeType': 'application/json',
      },
    });

    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw GeminiOcrException(
          'Gemini hatası (${res.statusCode}): ${_shortError(res.body)}');
    }

    final Map<String, dynamic> data = jsonDecode(res.body);
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
        as String?;
    if (text == null || text.trim().isEmpty) {
      throw const GeminiOcrException('Gemini boş yanıt döndü');
    }

    final cleaned = text
        .replaceAll(RegExp(r'^```json', multiLine: true), '')
        .replaceAll(RegExp(r'^```', multiLine: true), '')
        .trim();

    Map<String, dynamic> obj;
    try {
      obj = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      throw const GeminiOcrException('Gemini yanıtı çözümlenemedi');
    }

    final found = obj['found'] == true;
    if (!found) {
      throw const GeminiOcrException('Fotoğrafta tarih okunamadı');
    }

    final year = _int(obj['year']);
    final month = _int(obj['month']);
    var day = _int(obj['day']);

    if (year == null || month == null || month < 1 || month > 12) {
      throw const GeminiOcrException('Tarih eksik okundu');
    }
    // Gun yoksa ayin son gununu al (gida urununde guvenli kabul).
    day ??= _lastDayOfMonth(year, month);
    if (day < 1 || day > 31) {
      day = _lastDayOfMonth(year, month);
    }

    // Mantik kontrolu: cok eski (gecmis 2 yildan once) veya cok ileri
    // (10 yildan sonra) tarihler yanlis okuma sayilir.
    final result = DateTime(year, month, day);
    if (result.isBefore(DateTime(today.year - 2)) ||
        result.isAfter(DateTime(today.year + 10))) {
      throw const GeminiOcrException('Okunan tarih mantıksız görünüyor');
    }
    return result;
  }

  static int _lastDayOfMonth(int year, int month) {
    final firstNext = (month == 12)
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().replaceAll('*', '').trim();
    return s.isEmpty ? null : s;
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(
        v.toString().replaceAll('.', '').replaceAll(',', '.'));
  }

  static String _shortError(String body) {
    try {
      final m = jsonDecode(body);
      return (m['error']?['message'] as String?)
              ?.split('.')
              .first
              .substring(0, 80) ??
          'bilinmeyen';
    } catch (_) {
      return body.length > 80 ? body.substring(0, 80) : body;
    }
  }
}

class GeminiOcrException implements Exception {
  final String message;
  const GeminiOcrException(this.message);
  @override
  String toString() => message;
}
