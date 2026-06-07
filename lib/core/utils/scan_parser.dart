import 'date_utils.dart';

/// Taranan barkod/QR icerigini cozen yardimci.
/// QR formati: *8690504190554*29.95*22.10.2025*22.10.2025 08:37:36
/// (yildizlar ayrac, sirayla: barkod, fiyat, SKT, uretim/etiket tarihi-saati)
class ScanResult {
  final String raw;
  final String? barcode;
  final double? price;
  final DateTime? expiryDate;
  final DateTime? labelDateTime;

  const ScanResult({
    required this.raw,
    this.barcode,
    this.price,
    this.expiryDate,
    this.labelDateTime,
  });

  bool get isStructured => price != null || expiryDate != null;
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
      );
    }

    // Duz barkod (sadece rakam).
    return ScanResult(raw: trimmed, barcode: trimmed);
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
