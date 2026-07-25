import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'agent_nav_service.dart';
import 'ai_model_prefs.dart';
import 'price_change_service.dart';

/// Gemini Flash ile A4 fiyat degisim tablosunu yapilandirilmis JSON'a cevirir.
/// API anahtari cihazda sifreli saklanir (flutter_secure_storage).
/// Anahtar yoksa/istek basarisizsa cagiran ML Kit fallback'ine doner.
class GeminiOcrService {
  GeminiOcrService._();
  static final GeminiOcrService instance = GeminiOcrService._();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'gemini_api_key';

  /// MODEL FALLBACK ZINCIRI.
  /// Bu liste, kullanicinin KENDI API anahtarinda /models cagrisiyla
  /// dogrulanan, generateContent (gorseli okuyabilen) modellerden olusur.
  /// En iyi/hizli olandan baslayip, biri 404 verirse sonrakine gecer.
  ///   - gemini-2.5-flash      : multimodal, hizli, yuksek token limiti (1M)
  ///   - gemini-2.0-flash      : saglam yedek
  ///   - gemini-2.0-flash-001  : kararli surum
  ///   - gemini-2.0-flash-lite : en hafif/hizli yedek
  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
    'gemini-2.0-flash-lite',
  ];

  /// Yanittaki TUM metin parcalarini birlestirir (grounding/dusunme
  /// modellerinde yanit birden fazla part'a bolunebilir).
  static String _extractText(Map<String, dynamic> data) {
    final buf = StringBuffer();
    final cands = data['candidates'];
    if (cands is! List) return '';
    for (final c in cands) {
      final parts = (c as Map?)?['content']?['parts'];
      if (parts is! List) continue;
      for (final p in parts) {
        if (p is! Map) continue;
        // 'thought' parcalari cevabin kendisi degildir; atla.
        if (p['thought'] == true) continue;
        final t = p['text'];
        if (t is String && t.trim().isNotEmpty) buf.write(t);
      }
    }
    return buf.toString();
  }

  /// Metin gelmediyse nedenini dondurur (MAX_TOKENS, SAFETY, ...).
  static String? _finishReason(Map<String, dynamic> data) {
    final cands = data['candidates'];
    if (cands is List && cands.isNotEmpty) {
      final r = (cands.first as Map?)?['finishReason'];
      if (r is String && r.isNotEmpty) return r;
    }
    final fb = data['promptFeedback']?['blockReason'];
    if (fb is String && fb.isNotEmpty) return 'BLOCKED: $fb';
    return null;
  }

  /// Istek govdesini modele gore uyarlar (bkz. _generate aciklamasi).
  static String _tuneBodyForModel(String bodyJson, String model) {
    try {
      final map = jsonDecode(bodyJson) as Map<String, dynamic>;
      final cfg = Map<String, dynamic>.from(
          (map['generationConfig'] as Map?) ?? <String, dynamic>{});
      if (model.startsWith('gemini-2.5')) {
        cfg['thinkingConfig'] = {'thinkingBudget': 0};
        cfg['maxOutputTokens'] = cfg['maxOutputTokens'] ?? 8192;
      } else {
        cfg.remove('thinkingConfig'); // 2.0 bu alani tanimaz
      }
      map['generationConfig'] = cfg;
      return jsonEncode(map);
    } catch (_) {
      return bodyJson; // bozulmasindansa oldugu gibi gonder
    }
  }

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<void> setApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());
  Future<void> clearApiKey() => _storage.delete(key: _keyName);
  Future<bool> hasApiKey() async {
    final k = await getApiKey();
    return k != null && k.isNotEmpty;
  }

  /// Verilen istek govdesini model listesini deneyerek Gemini'ye gonderir.
  /// Bir model 404 (model bulunamadi) verirse SONRAKI modele gecer. Diger
  /// hatalarda (401/403/429 vb.) hemen durur cunku model degisimi cozmez.
  /// Basarili yanitin metin icerigini doner.
  Future<String> _generate(String apiKey, String bodyJson) async {
    GeminiOcrException? lastError;

    // Kullanici Ayarlar'dan bir model sectiyse ONU ilk sirada dene; kalan
    // otomatik yedekler ardindan gelir (secili model tekrar edilmez).
    final selected = AiModelPrefs.instance.selected;
    final tryModels = <String>[
      if (selected != null && selected.isNotEmpty) selected,
      ..._models.where((m) => m != selected),
    ];

    for (final model in tryModels) {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');

      // Govdeyi MODELE GORE uyarla: 2.5 ailesi "dusunen" modeller —
      // dusunme tokenleri butceyi yiyip metinsiz (bos) yanit birakabilir.
      // Bu yuzden dusunme kapatilir ve cikti tavani yukseltilir. 2.0
      // modelleri bu alani TANIMAZ (400 verir), onlarda temizlenir.
      final body = _tuneBodyForModel(bodyJson, model);

      final http.Response res;
      try {
        res = await http
            .post(uri,
                headers: {'Content-Type': 'application/json'},
                body: body)
            .timeout(const Duration(seconds: 45));
      } catch (e) {
        lastError = GeminiOcrException('Bağlantı hatası: $e');
        continue; // ag hatasinda sonraki modeli de dene
      }

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        // ONEMLI: Google Arama (grounding) ve "dusunen" 2.5 modelleri
        // yaniti TEK parca dondurmez. Eskiden sadece parts[0].text
        // okunuyordu; ilk parca metin icermeyince "bos yanit" hatasi
        // aliniyordu. Artik TUM candidate'lerin TUM part'lari birlestirilir.
        final text = _extractText(data);
        if (text.trim().isNotEmpty) return text;

        // Metin yoksa nedenini ogren (MAX_TOKENS / SAFETY / RECITATION).
        final reason = _finishReason(data);
        lastError = GeminiOcrException(
            'Gemini boş yanıt döndü ($model'
            '${reason == null ? '' : ' · $reason'})');
        // Bos yanitta HEMEN PES ETME: sonraki modeli dene. Ozellikle
        // 2.5 "dusunme" butcesi tukendiginde baska model calisir.
        continue;
      }

      // 404 = model adi gecersiz, 400 = bu model istegi kabul etmedi
      // (or. desteklenmeyen alan) -> sonraki modeli dene.
      if (res.statusCode == 404 || res.statusCode == 400) {
        lastError = GeminiOcrException(
            'Model reddetti ($model): ${_shortError(res.body)}');
        continue;
      }

      // Diger hatalar (401 anahtar, 403 yetki, 429 kota...) model
      // degisimiyle cozulmez; hemen bildir.
      throw GeminiOcrException(
          'Gemini hatası (${res.statusCode}): ${_shortError(res.body)}');
    }

    // Tum modeller 404 verdi veya baglanti kurulamadi.
    throw lastError ??
        const GeminiOcrException('Hiçbir Gemini modeli yanıt vermedi');
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

    final text = await _generate(key, body);

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

    final text = await _generate(key, body);

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

  /// ÜRÜN ADI OKUMA (raf etiketinden).
  /// Etiket fotografindan urun adini okuyup duzgun bir metin dondurur.
  /// Bulamazsa/hata olursa GeminiOcrException firlatir (cagiran elle
  /// girise veya "Etiketten Oku" butonuna yonlendirir).
  Future<String> extractProductName(File image) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('API anahtarı yok');
    }

    final bytes = await image.readAsBytes();
    final b64 = base64Encode(bytes);

    const prompt = '''
Bu fotoğraf bir market raf etiketi veya ürün ambalajıdır. Üzerinde ürün adı yazıyor olabilir (örnek: "ÜLK.DANKEK POTİ MUFFİN SADE 20GR" veya ürün paketindeki marka+isim).
Görüntüdeki ÜRÜN ADINI bul ve SADECE şu formatta tek satır JSON döndür (başka hiçbir şey yazma):
{"name":"ÜRÜN ADI","found":true}
Kurallar:
- found: ürün adı net okunduysa true, okunamadıysa false.
- name: kısaltmaları AÇMA, etikette/ambalajda yazdığı gibi bırak. Gramaj/ebat bilgisini (örn. "20GR") da isme dahil et.
- Fiyat, barkod, tarih gibi diğer alanları YAZMA, sadece ürün adını ver.
- found false ise name boş string olabilir.
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

    final text = await _generate(key, body);

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
    final name = _str(obj['name']);
    if (!found || name == null || name.isEmpty) {
      throw const GeminiOcrException('Etikette ürün adı okunamadı');
    }
    return name;
  }

  /// KONTROL LISTESI TABLOSU OKUMA (yonetici fotografi).
  /// Yoneticinin attigi urun listesi fotografini Gemini'ye gonderir,
  /// satirlari (sektor, kategori, stok kodu, barkod, stok adi, stok, rbg,
  /// son giris, son satis) yapilandirilmis JSON olarak dondurur.
  /// Hata durumunda GeminiOcrException firlatir.
  ///
  /// Donen ham Map listesi (cagiran ControlListItem'a cevirir):
  ///   sector, category, stockCode, barcode, productName, stock, rbgDays,
  ///   lastEntry, lastSale
  Future<List<Map<String, dynamic>>> extractStockTable(File image) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('API anahtarı yok');
    }

    final bytes = await image.readAsBytes();
    final b64 = base64Encode(bytes);

    const prompt = '''
Bu görüntü bir market stok/kontrol tablosudur. Sütunlar şunlar olabilir: Sektör, Kategori, Stok Kodu, Barkod, Stok Adı, Stok, RBG (Gün), Son Giriş, Son Satış.
Tablodaki HER satırı oku ve SADECE şu formatta bir JSON dizisi döndür (başka hiçbir metin/açıklama yazma):
[{"sector":"ANPA - ATISTIRMALIK","category":"CIPS","stockCode":"34010253","barcode":"8690624203110","productName":"FRI.DORITOS 109 GR MEXICANO ACI SUPER","stock":24,"rbgDays":1,"lastEntry":"11.05.2026","lastSale":"26.06.2026"}]
Kurallar:
- barcode: 12-13 haneli uzun sayı (Stok Kodu DEĞİL). Stok Kodu daha kısadır (6-9 hane).
- stock: "Stok" sütunundaki adet (tam sayı).
- rbgDays: "RBG" sütunundaki gün sayısı (tam sayı).
- lastEntry = "Son Giriş", lastSale = "Son Satış" sütunları; tarihi gördüğün gibi metin olarak bırak (örn. "11.05.2026").
- productName: yıldız (*) karakterlerini ve parantez içi kod eklerini KORU, gördüğün gibi yaz.
- Okunamayan alanı null yap, ama satırı ATLAMA (barkod veya stok adı varsa satırı dahil et).
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

    final text = await _generate(key, body);

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

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final barcode = _str(row['barcode']);
      final name = _str(row['productName']);
      // Barkod VEYA urun adi yoksa anlamsiz satir, atla.
      if (barcode == null && name == null) continue;
      result.add({
        'sector': _str(row['sector']),
        'category': _str(row['category']),
        'stockCode': _str(row['stockCode']),
        'barcode': barcode,
        'productName': name,
        'stock': _int(row['stock']),
        'rbgDays': _int(row['rbgDays']),
        'lastEntry': _str(row['lastEntry']),
        'lastSale': _str(row['lastSale']),
      });
    }
    if (result.isEmpty) {
      throw const GeminiOcrException('Tabloda satır bulunamadı');
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

  /// ════════════════════════════════════════════════════════════════════
  ///  DEPO ASISTANI SOHBET — Google Arama destekli
  /// ────────────────────────────────────────────────────────────────────
  ///  Once telefondaki YEREL veri (reyon konumlari, urun dizini) verilir.
  ///  Yerel veri yetmezse Gemini, Google Arama araciyla internetten arayip
  ///  daha detayli cevap uretir. Turkce, kisa ve net yanit verir.
  ///
  ///  [context]  : yerel veri ozeti (reyonlar, urunler, konumlari).
  ///  [history]  : onceki mesajlar — her biri {'role':'user'|'model','text':..}
  ///  [question] : kullanicinin son sorusu.
  /// ════════════════════════════════════════════════════════════════════
  Future<String> assistantAnswer({
    required String context,
    required List<Map<String, String>> history,
    required String question,
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('API anahtarı yok');
    }

    final preamble =
        'Sen SKT Takip uygulamasının içinde çalışan, uygulamaya TAM '
        'HAKİM bir Türkçe asistansın (agent).\n'
        'UYGULAMANIN ÖZELLİKLERİ (hepsini sen de yapabilirsin): SKT/son '
        'kullanma takibi (ürün ekle/güncelle/imha-iade/sil), barkod dizini, '
        'depo-palet-raf yönetimi, reyon dizilimi (ürünü rafa yerleştirme), '
        'teşhir listesi, reyona açılacaklar, veri yedekleme, fiyat değişim ve '
        'fiyat kontrol akışları, etiket basım kuyruğu, sayım, vardiya, '
        'kontrol listeleri, ÇALIŞMA PROGRAMI/ALARMLAR (haftalık saat '
        'alarmları) ve uygulama ayarları (tema, kilit/şifre, ses...).\n'
        'ASLA "bu özellik bulunmuyor / yapamam" DEME. İstenen şey '
        'yukarıdakilerden biriyse ilgili EYLEM bloğunu üret; emin '
        'değilsen önce ARAÇLARLA veritabanına bak.\n'
        'YAZIM: Kullanıcı çoğu zaman sesli yazdırır; harf hataları ve '
        'eksik harfler olur ("aalrm kur" = "alarm kur", "ku4" = "kur"). '
        'Harfi harfine takılma, NİYETİ anla. Gerçekten anlaşılmıyorsa tek '
        'bir kısa soru sor.\n\n'
        'Sen bir market/mağaza çalışanına yardım eden Türkçe asistansın. '
        'Aşağıdaki bölümler mağazanın GÜNCEL verileridir:\n'
        '(1) REYON KONUMLARI — ürünlerin hangi reyon/sütun/rafta olduğu.\n'
        '(2) KAYITLI ÜRÜNLER — sistemde kayıtlı ama yeri girilmemiş ürünler.\n'
        '(3) SKT TAKİBİ — ürünlerin son kullanma tarihleri ve kalan günler.\n'
        '(4) DURUM — vardiya ve etiket basım kuyruğu.\n'
        'Kurallar:\n'
        '- Yer soruları: ÖNCE REYON KONUMLARI\'ndan bul; "Reyon adı, Sütun X, '
        'Raf Y" biçiminde net söyle.\n'
        '- SKT soruları ("bu hafta dolan var mı", "hangi ürün önce bozulur"): '
        'SKT TAKİBİ bölümünden hesapla ve tarihleriyle söyle.\n'
        '- Vardiya/etiket soruları: DURUM bölümünden cevapla.\n'
        '- Ürün kayıtlıysa ama yeri yoksa: "Sistemde kayıtlı ama rafta yeri '
        'henüz girilmemiş" de.\n'
        '- Hiçbir listede yoksa ya da genel bilgi (içerik, marka, muadil) '
        'gerekiyorsa GOOGLE ARAMA ile internetten araştır.\n'
        '- Kısa, net ve Türkçe yanıt ver. Uydurma; emin değilsen söyle.\n'
        '- ÜRÜN ATIFI: Sistemde kayıtlı bir üründen bahsederken cevabının '
        'içine AYRI BİR SATIR olarak [[urun:BARKOD|GÖRÜNEN AD]] yaz '
        '(örn. [[urun:8691573091087|Burcu Domates Rendesi 685g]]). '
        'Uygulama bunu ürünün FOTOĞRAFLI, tıklanabilir kartına çevirir ve '
        'kullanıcı dokununca ürün detay sayfası açılır. Yer/SKT/stok '
        'cevaplarında ilgili ürün(ler) için MUTLAKA bu atıfı ekle; barkodu '
        'listelerdeki köşeli parantezden al, uydurma.\n\n'
        '=== SEN BİR AGENT\'SIN (ARAÇLAR) ===\n'
        'Sabit bir özellik listesine BAĞLI DEĞİLSİN. Uygulamanın TÜM '
        'verisi SQLite\'ta, TÜM ayarları güvenli depoda. Bilmediğin '
        'bir şey sorulursa ÖNCE ARAÇLARLA KEŞFET, sonra cevapla. '
        '"Bu özelliğim yok" DEME — önce bak.\n'
        'Araç çağırmak için (cevabına ekle, uygulama çalıştırıp sonucu '
        'sana geri verir, sonra devam edersin):\n'
        '```tool\n'
        '{"tool":"db_schema"}\n'
        '```\n'
        'Kullanılabilir araçlar (SADECE OKUMA, otomatik çalışır):\n'
        '- db_schema: {"tool":"db_schema"} tüm tabloları+kayıt sayılarını '
        'verir. {"tool":"db_schema","table":"products"} o tablonun '
        'kolonlarını + örnek satırını verir.\n'
        '- db_query: {"tool":"db_query","sql":"SELECT ..."} — tek SELECT '
        '(veya PRAGMA/WITH). Sayım, filtreleme, JOIN, GROUP BY serbest.\n'
        '- prefs_list: {"tool":"prefs_list"} tüm uygulama ayarlarını '
        '(anahtar=değer) listeler; {"prefix":"theme"} ile filtrelenir.\n'
        '- shell_run: {"tool":"shell_run","command":"ls ~"} Termux\'ta '
        'ZARARSIZ komut çalıştırır (ls, cat, grep, df, pkg search...). '
        'Sistemi değiştiren komutlar burada ÇALIŞMAZ.\n'
        '- read_screen: {"tool":"read_screen"} ekranda görünen metinleri '
        'okur — nereye dokunacağını bilmek için önce bunu kullan.\n'
        '- memory_list: {"tool":"memory_list"} daha önce öğrendiğin '
        'kuralları/hataları listeler.\n'
        '- list_apps: {"tool":"list_apps"} telefonda KURULU uygulamaları '
        '(ad → paket) listeler. {"tool":"list_apps","query":"termux"} ile '
        'süzülür. Bir uygulamayı açmadan önce doğru PAKET adını buradan bul.\n'
        'Araç kullanımı kuralları:\n'
        '- Yukarıdaki araçların HEPSİ TANIMLIDIR ve ÇALIŞIR. Bir aracı '
        '"tanımlı değil / bulunamadı" diye REDDETME; ```tool bloğunu yaz, '
        'uygulama çalıştırıp sonucu sana verir. Sonuç hata dönerse GERÇEK '
        'hata mesajını kullanıcıya aktar (uydurma).\n'
        '- Araç adını tam yaz: db_schema, db_query, prefs_list, shell_run, '
        'read_screen, memory_list, list_apps. Yaklaşık ad da çözülür ama '
        'tam adı tercih et; OLMAYAN bir araç uydurma.\n'
        '- Telefonda komut çalıştırmak (saat, tarih, dosya, sistem bilgisi) '
        'için shell_run kullan (örn. {"tool":"shell_run","command":"date"}). '
        'Sistemi değiştiren komutlar için shell_exec EYLEMİ (onay kartı).\n'
        '- ASLA "birazdan bakarım / şimdi kontrol ediyorum / cevap '
        'vereceğim / bir saniye" deyip DURMA. Kullanıcı senden ikinci bir '
        'mesaj BEKLEYEMEZ. Her cevabın YA nihai sonucu içerir YA DA aynı '
        'mesajda bir ```tool çağrısı/```action bloğu içerir. Bir işi '
        'yapacaksan konuşmadan O ANDA aracı çağır.\n'
        '- Bir turda birden fazla araç çağırabilirsin. Sonuçları görünce '
        'gerekirse YENİ araç çağır (en fazla 4 tur).\n'
        '- Tablo/kolon adını TAHMİN ETME; önce db_schema ile bak.\n'
        '- Araç bloğu ürettiğin turda uzun açıklama yazma; kısa bir '
        'cümle yeter.\n\n'
        '=== SİSTEMDE İŞLEM YAPMA (EYLEMLER) ===\n'
        'Kullanıcı bir DEĞİŞİKLİK isterse (ürün ekle/çıkar, palet '
        'oluştur/sil/taşı, depo veya reyon oluştur/sil, SKT takibine ürün '
        'ekle) SEN İŞLEMİ DOĞRUDAN YAPMAZSIN; bunun yerine cevabının SONUNA '
        'bir EYLEM BLOĞU eklersin. Uygulama bu bloğu kullanıcıya ONAY '
        'kartı olarak gösterir; kullanıcı onaylayınca işlem çalışır.\n'
        'Biçim (aynen, kod bloğu olarak):\n'
        '```action\n'
        '{"type":"...","...":"..."}\n'
        '```\n'
        'Birden fazla işlem gerekiyorsa birden fazla ```action bloğu '
        'ekleyebilirsin. Desteklenen type değerleri ve alanları:\n'
        '- add_pallet_item: pallet_code, barcode, name, quantity, expiry '
        '(opsiyonel, gg.aa.yyyy)\n'
        '- remove_pallet_item: pallet_code, barcode (veya ürün adı), quantity\n'
        '- create_pallet: warehouse_name (opsiyonel), code, floor (true/false)\n'
        '- delete_pallet: pallet_code\n'
        '- move_pallet: pallet_code, column, row (veya to_waiting:true / '
        'to_floor:true)\n'
        '- create_warehouse: name\n'
        '- create_shelf_unit: name, sections (sütun sayısı)\n'
        '- delete_shelf_unit: name\n'
        '- add_skt_product: name, barcode, expiry (gg.aa.yyyy), quantity\n'
        '- update_product: barcode, quantity (opsiyonel), expiry (opsiyonel, '
        'gg.aa.yyyy), all (true=tüm partiler; boşsa en yakın SKT partisi). '
        'Mevcut bir SKT kaydının adedini/tarihini düzeltir.\n'
        '- dispose_product: barcode, status ("disposed"=imha [varsayılan] | '
        '"returned"=iade), all (opsiyonel). Ürünü imhaya/iadeye taşır '
        '(geçmişe düşer). "bu ürünü imha et / attım / iade et" için BUNU '
        'kullan; kaydı SİLME.\n'
        '- delete_product: barcode, all (opsiyonel). SKT kaydını tamamen '
        'siler (imha DEĞİL — kayıt tümden yok olur, geçmişe düşmez). '
        'Sadece yanlış girilmiş kayıt için.\n'
        '- place_shelf_slot: barcode, unit (reyon adı; boşsa ilk reyon), '
        'column (sütun no), row (raf no), name (opsiyonel). Bir ürünü '
        'reyon konumuna yerleştirir; "X ürününü şu reyona/rafa koy / '
        'yerini kaydet" için kullan.\n'
        '- create_backup: (alan yok) veritabanı + tüm fotoğrafları ZIP '
        'olarak yedekler ve paylaşım menüsünü açar. "yedek al / dışa '
        'aktar / verilerimi kaydet" için.\n'
        '--- TELEFONU KULLANMA (kullanıcının yerine dokun) ---\n'
        '- tap_text: text — ekranda o yazıyı bulup DOKUNUR. Önce '
        'read_screen ile ekranı gör, sonra doğru yazıyı seç.\n'
        '- global_action: action ("back" | "home" | "recents" | '
        '"notifications").\n'
        '- open_app: package (ör. com.termux) VE/VEYA name (uygulama adı, '
        'ör. "Termux"). Başka uygulamayı açar. Paketi bilmiyorsan ÖNCE '
        'list_apps aracıyla bul, sonra bu EYLEMİ üret; name verirsen paket '
        'ada göre çözülür. Termux paketi: com.termux.\n'
        '--- TERMUX (gerçek terminal) ---\n'
        '- shell_exec: command, description (Türkçe amaç). Sistemi '
        'değiştiren komutlar (pkg install, dosya yazma, git...) için. '
        'ONAY KARTI çıkar. Yıkıcı komutlar süzgeçte engellenir.\n'
        '--- ÖĞRENME (kullanıcıyı hatalardan koru) ---\n'
        '- remember: note, kind ("kural"|"hata"|"tercih"). Kullanıcının '
        'tekrarladığı bir hatayı ya da tercihini fark edersen KAYDET; '
        'sonraki sefer önceden uyarırsın.\n'
        '--- UYGULAMAYI KULLANMA (kullanıcının yerine) ---\n'
        '- open_screen: screen (ekran anahtarı). Kullanıcı "şuraya git", '
        '"aç", "göster" derse ya da bir işi orada yapması gerekiyorsa '
        'EKRANI SEN AÇ. Kullanılabilir anahtarlar: ${AgentNavService.keyList}.\n'
        '--- BARKOD DİZİNİ ---\n'
        '- add_barcode_entry: barcode, name, stockCode (opsiyonel). '
        'Ürün adı ↔ barkod eşleştirmesini dizine kaydeder. '
        '"Ürünü veritabanına/sisteme ekle" denince SKT (son kullanma '
        'tarihi) verilmemişse DOĞRU EYLEM BUDUR.\n'
        '--- ALARM / ÇALIŞMA PROGRAMI ---\n'
        '- add_alarm: hour (0-23), minute (0-59), days ("hergun" ya da '
        '"1,2,3" — 1=Pzt...7=Paz; boşsa BUGÜN), label (opsiyonel). '
        'Haftalık tekrar eden gerçek alarm kurar (telefon çalar).\n'
        '- delete_alarm: hour, minute, days (opsiyonel; boşsa o saatteki '
        'tüm günler) — alarmı iptal eder ve programdan siler.\n'
        '--- UYGULAMA AYARLARI (sen uygulamaya tam hakimsin) ---\n'
        '- set_theme: mode ("light" | "dark" | "system")\n'
        '- set_app_lock: enabled (true/false) — uygulama kilidi\n'
        '- change_pin: pin ("4-8 haneli rakam") — uygulama şifresini '
        'değiştirir ve kilidi açar\n'
        '- set_biometric: enabled (true/false) — parmak izi girişi\n'
        '- set_location_reveal: enabled (true/false) — konum canlandırma '
        'animasyonları\n'
        '- set_company_flow: enabled (true/false) — şirket uygulamasına '
        'otomatik geçiş entegrasyonu\n'
        '- add_teshir: barcode, name, note (teşhir yeri, opsiyonel)\n'
        '- remove_teshir: barcode\n'
        '- add_restock: barcode, name, quantity (reyona açılacaklar)\n'
        '- clear_notifications: (alan yok) bekleyen tüm SKT bildirimlerini '
        'iptal eder\n'
        '- set_free_mode: enabled (true/false) — SERBEST MOD. Açıkken '
        'ürettiğin eylemler ve sistem komutları onay BEKLEMEDEN otomatik '
        'çalışır. "serbest modu kapat/aç", "otomatik yap", "bana sorma" '
        'gibi isteklerde kullan.\n'
        '--- GENEL AMAÇLI (hazır eylem yoksa BUNLARI kullan) ---\n'
        '- db_write: sql (tek INSERT/UPDATE/DELETE/ALTER/CREATE ifadesi), '
        'description (ne yapacağının Türkçe özeti), title (onay kartı '
        'başlığı). SON ÇARE — yukarıdaki hazır eylemlerden biri işi '
        'görüyorsa ONU kullan, db_write yazma.\n'
        '  · Ürün + SKT ekleme → add_skt_product (products tablosunda '
        'expiry_date ZORUNLUDUR, ham INSERT hata verir).\n'
        '  · Ürün adı + barkod → add_barcode_entry.\n'
        '  · db_write kullanacaksan ÖNCE db_schema ile o tablonun '
        '[NOT NULL] kolonlarını gör ve HEPSİNİ INSERT içine koy.\n'
        '- prefs_set: key, value — herhangi bir uygulama ayarını yazar. '
        'Anahtarı önce prefs_list ile bul (şifre/API anahtarı hariç).\n'
        'Kurallar:\n'
        '- HİÇBİR İSTEĞE "yapamam/özelliğim yok" DEME. Hazır bir eylem '
        'yoksa db_write / prefs_set ile çöz; gerçekten imkânsızsa NEDENİNİ '
        'açıkla. Önce araçlarla keşfetmeden reddetme.\n'
        '- "Alarm/bildirim kuramam", "tema değiştiremem", "şifre '
        'değiştiremem" DEME. Yukarıdaki eylemlerle uygulamanın ayarlarını '
        'DEĞİŞTİREBİLİRSİN; kullanıcı isterse ilgili eylem bloğunu üret.\n'
        '- Şifre değiştirme gibi güvenlik işlemlerinde bloğu üretmeden önce '
        'yeni şifreyi net öğren (kullanıcı söylemediyse SOR).\n'
        '- Eylemi üretmeden önce elindeki verilerle alanları OLABILDIĞINCE '
        'doldur (ör. ürün adını dizinden bul). Eksik ve KRİTİK bir bilgi '
        'varsa (ör. hangi palet) önce kullanıcıya SOR, blok üretme.\n'
        '- Eylem bloğunun hemen öncesinde tek cümlelik düz Türkçe özet yaz '
        '(ör. "Şunu yapmamı onaylıyor musun:").\n'
        '- Silme gibi geri alınamaz işlemlerde kullanıcıyı kısaca uyar.\n'
        '- Kullanıcı sadece bilgi soruyorsa EYLEM BLOĞU ÜRETME.\n\n'
        '$context';

    final contents = <Map<String, dynamic>>[
      {
        'role': 'user',
        'parts': [
          {'text': preamble}
        ]
      },
      {
        'role': 'model',
        'parts': [
          {'text': 'Anladım, hazırım. Sorunuzu bekliyorum.'}
        ]
      },
    ];

    for (final m in history) {
      contents.add({
        'role': m['role'] == 'user' ? 'user' : 'model',
        'parts': [
          {'text': m['text'] ?? ''}
        ],
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': question}
      ],
    });

    final body = jsonEncode({
      'contents': contents,
      // Yerel veri yetmezse internetten arayabilsin diye Google Arama araci.
      'tools': [
        {'google_search': <String, dynamic>{}}
      ],
      'generationConfig': {'temperature': 0.3},
    });

    return _generate(key, body);
  }

  /// ETIKET FOTOGRAFINDAN fiyat + barkod okur (QR'siz etiketler icin).
  /// Fiyat Kontrol'un "fotografla oku" akisinda kullanilir.
  Future<({String? barcode, double? price})> extractLabelPrice(
      File image) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const GeminiOcrException('API anahtarı yok');
    }
    final b64 = base64Encode(await image.readAsBytes());
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text': 'Bu bir market RAF ETİKETİ fotoğrafı. Etiketteki '
                  'SATIŞ FİYATINI ve BARKOD NUMARASINI oku. SADECE şu '
                  'JSON ile cevap ver, başka hiçbir şey yazma: '
                  '{"barcode":"8690...","price":12.5} '
                  'Barkod okunamıyorsa null, fiyat okunamıyorsa null yaz. '
                  'Fiyatı nokta ondalıklı sayı olarak ver (₺ işareti olmadan). '
                  'Birden fazla fiyat varsa BÜYÜK PUNTOLU olanı (satış '
                  'fiyatı) al; birim fiyatı (₺/kg) ALMA.'
            },
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
            },
          ]
        }
      ],
      'generationConfig': {'temperature': 0.0},
    });
    final raw = await _generate(key, body);
    final clean = raw.replaceAll(RegExp(r'```json|```'), '').trim();
    final m = jsonDecode(clean) as Map<String, dynamic>;
    final bc = m['barcode']?.toString();
    return (
      barcode: (bc == null || bc == 'null' || bc.isEmpty) ? null : bc,
      price: _num(m['price']),
    );
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
