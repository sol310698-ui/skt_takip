import 'date_utils.dart';

/// Taranan icerigin turu.
enum ScanKind {
  /// Yildizli yapisal etiket QR'i: *barkod*fiyat*SKT*basim
  labelQr,

  /// Duz urun barkodu (sadece rakam, EAN-13/EAN-8 vb.)
  plainBarcode,

  /// Tanimsiz serbest metin (barkod sayilamaz).
  freeText,
}

/// Taranan barkod/QR icerigini cozen yardimci.
/// QR formati: *8690504190554*29.95*22.10.2025*22.10.2025 08:37:36
/// (yildizlar ayrac, sirayla: barkod, fiyat, SKT, uretim/etiket tarihi-saati)
class ScanResult {
  final String raw;
  final String? barcode;
  final double? price;
  final DateTime? expiryDate;
  final DateTime? labelDateTime;
  final ScanKind kind;

  /// KOLI/DEPO BARKODU (ITF-14 / GTIN-14) okunduysa ORIJINAL 14 haneli
  /// kod burada durur; [barcode] ise ondan turetilmis PERAKENDE EAN-13
  /// olur. Boylece hem kolinin kendi kodu kaybolmaz hem de urun
  /// dizinindeki (Excel) barkodla eslesme saglanir.
  final String? caseBarcode;

  const ScanResult({
    required this.raw,
    this.barcode,
    this.price,
    this.expiryDate,
    this.labelDateTime,
    this.kind = ScanKind.freeText,
    this.caseBarcode,
  });

  /// Koli barkodundan turetilmis bir urun barkodu mu?
  bool get isFromCase => caseBarcode != null;

  bool get isStructured => price != null || expiryDate != null;

  /// Yapisal etiket QR'i mi (fiyat/SKT tasiyabilen).
  bool get isLabel => kind == ScanKind.labelQr;

  /// Urun barkodu olarak kullanilabilir mi (duz barkod veya etiket icindeki barkod).
  bool get hasUsableBarcode =>
      barcode != null &&
      barcode!.isNotEmpty &&
      kind != ScanKind.freeText;

  /// Verilen serbest metnin gecerli bir barkod olup olmadigini soyler.
  /// 8-14 hane arasi salt rakam barkod kabul edilir (EAN-8/EAN-13/ITF-14).
  static bool looksLikeBarcode(String s) {
    final t = s.trim();
    return RegExp(r'^\d{8,14}$').hasMatch(t);
  }
}

class ScanParser {
  ScanParser._();

  static ScanResult parse(String raw) {
    final trimmed = raw.trim();

    // Yildizli yapisal QR formati mi?
    if (trimmed.contains('*')) {
      final parts = trimmed
          .split('*')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      String? barcode;
      double? price;
      DateTime? expiry;
      DateTime? labelDt;

      if (parts.isNotEmpty) barcode = parts[0];
      if (parts.length > 1) price = _parsePrice(parts[1]);
      if (parts.length > 2) expiry = DateUtils.parseFromOcr(parts[2]);
      if (parts.length > 3) labelDt = _parseDateTime(parts[3]);

      return ScanResult(
        raw: trimmed,
        barcode: barcode,
        price: price,
        expiryDate: expiry,
        labelDateTime: labelDt,
        kind: ScanKind.labelQr,
      );
    }

    // GS1-128 / EAN-128: "(01)28691440077279" ya da "0128691440077279"
    // gibi AI'li iceriklerden GTIN-14'u ayikla.
    final gtinFromAi = _gtinFromGs1(trimmed);
    if (gtinFromAi != null) {
      final retail = retailFromGtin14(gtinFromAi);
      return ScanResult(
        raw: trimmed,
        barcode: retail ?? gtinFromAi,
        caseBarcode: retail == null ? null : gtinFromAi,
        kind: ScanKind.plainBarcode,
      );
    }

    // Duz barkod (sadece rakam) mu, yoksa serbest metin mi?
    if (ScanResult.looksLikeBarcode(trimmed)) {
      // KOLI BARKODU DONUSUMU: 14 haneli ITF-14/GTIN-14 okunduysa
      // icindeki PERAKENDE EAN-13'u cikar (urun dizini bununla eslesir).
      final retail = retailFromGtin14(trimmed);
      return ScanResult(
        raw: trimmed,
        barcode: retail ?? trimmed,
        caseBarcode: retail == null ? null : trimmed,
        kind: ScanKind.plainBarcode,
      );
    }

    // Tanimsiz icerik - barkod olarak kullanilmamali.
    return ScanResult(raw: trimmed, barcode: null, kind: ScanKind.freeText);
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  KOLI (ITF-14 / GTIN-14) → PERAKENDE (EAN-13) DONUSUMU
  /// ──────────────────────────────────────────────────────────────────
  ///  Koli barkodu su yapidadir:
  ///     [gosterge][EAN-13'un ilk 12 hanesi][ITF-14 kontrol hanesi]
  ///  Ornek: 2 8691440 07727 9  →  gosterge=2, govde=869144007727
  ///  Perakende barkod = govde + EAN-13 kontrol hanesi (YENIDEN hesaplanir;
  ///  ITF-14'un kontrol hanesi FARKLIDIR, oldugu gibi kullanilamaz).
  ///     869144007727 → kontrol 5 → 8691440077275
  ///  Gecersiz/uyumsuz durumda null doner (donusum yapilmaz).
  /// ══════════════════════════════════════════════════════════════════
  static String? retailFromGtin14(String code) {
    final t = code.trim();
    if (!RegExp(r'^\d{14}$').hasMatch(t)) return null;
    // Once GTIN-14'un kendi kontrol hanesi dogru mu? Degilse bu gercek
    // bir koli barkodu olmayabilir; dokunma.
    if (!_gtinCheckOk(t)) return null;
    final body = t.substring(1, 13); // gostergeyi ve kontrolu at
    final check = _eanCheckDigit(body);
    return '$body$check';
  }

  /// 12 haneli govdeden EAN-13 kontrol hanesi.
  static int _eanCheckDigit(String body12) {
    var sum = 0;
    for (var i = 0; i < body12.length; i++) {
      final d = int.parse(body12[i]);
      sum += (i % 2 == 0) ? d : d * 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  /// GTIN-14 kontrol hanesi dogrulamasi (sagdan sola 3,1,3,1...).
  static bool _gtinCheckOk(String v) {
    if (v.length != 14) return false;
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      final d = int.tryParse(v[i]);
      if (d == null) return false;
      // Soldan i=0 icin agirlik 3 (14 hanede sagdan sola 3,1,3,1...).
      sum += (i % 2 == 0) ? d * 3 : d;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == int.tryParse(v[13]);
  }

  /// GS1-128 icinden AI (01) GTIN-14'unu ayiklar.
  /// Kabul edilen bicimler: "(01)XXXXXXXXXXXXXX", "01XXXXXXXXXXXXXX"
  /// (ardindan baska AI'lar gelebilir).
  static String? _gtinFromGs1(String s) {
    final paren = RegExp(r'\(01\)\s*(\d{14})').firstMatch(s);
    if (paren != null) return paren.group(1);
    // Parantezsiz: basta 01 + 14 hane (toplam en az 16 karakter, hepsi rakam
    // olmak zorunda degil — sonrasinda baska AI'lar olabilir).
    final plain = RegExp(r'^01(\d{14})').firstMatch(s.replaceAll(' ', ''));
    if (plain != null) return plain.group(1);
    return null;
  }

  static double? _parsePrice(String s) {
    final cleaned = s.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned);
  }

  /// "22.10.2025 08:37:36" -> DateTime
  static DateTime? _parseDateTime(String s) {
    final dateMatch =
        RegExp(r'(\d{1,2})[./](\d{1,2})[./](\d{4})').firstMatch(s);
    if (dateMatch == null) return DateUtils.parseFromOcr(s);

    final d = int.tryParse(dateMatch.group(1)!);
    final m = int.tryParse(dateMatch.group(2)!);
    final y = int.tryParse(dateMatch.group(3)!);
    if (d == null || m == null || y == null) return null;

    int hh = 0, mm = 0, ss = 0;
    final timeMatch = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(s);
    if (timeMatch != null) {
      hh = int.tryParse(timeMatch.group(1)!) ?? 0;
      mm = int.tryParse(timeMatch.group(2)!) ?? 0;
      ss = int.tryParse(timeMatch.group(3) ?? '0') ?? 0;
    }
    try {
      return DateTime(y, m, d, hh, mm, ss);
    } catch (_) {
      return null;
    }
  }
}
