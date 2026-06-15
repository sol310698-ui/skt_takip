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
