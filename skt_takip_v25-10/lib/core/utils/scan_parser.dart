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

  const ScanResult({
    required this.raw,
    this.barcode,
    this.price,
    this.expiryDate,
    this.labelDateTime,
    this.kind = ScanKind.freeText,
  });

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

    // Duz barkod (sadece rakam) mu, yoksa serbest metin mi?
    if (ScanResult.looksLikeBarcode(trimmed)) {
      return ScanResult(
        raw: trimmed,
        barcode: trimmed,
        kind: ScanKind.plainBarcode,
      );
    }

    // Tanimsiz icerik - barkod olarak kullanilmamali.
    return ScanResult(raw: trimmed, barcode: null, kind: ScanKind.freeText);
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
