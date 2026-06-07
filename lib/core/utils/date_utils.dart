import '../constants/app_constants.dart';

/// Tarih hesaplama ve OCR metninden tarih ayıklama yardımcıları.
class DateUtils {
  DateUtils._();

  /// SKT'ye kalan gün sayısı (negatif = geçmiş).
  static int daysUntil(DateTime expiry) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(expiry.year, expiry.month, expiry.day);
    return target.difference(today).inDays;
  }

  /// SKT'ye göre durum belirler.
  static ExpiryStatus statusFor(DateTime expiry) {
    final days = daysUntil(expiry);
    if (days < 0) return ExpiryStatus.expired;
    if (days <= AppConstants.criticalDays) return ExpiryStatus.critical;
    if (days <= AppConstants.warningDays) return ExpiryStatus.warning;
    return ExpiryStatus.safe;
  }

  /// OCR ile okunan ham metinden tarih ayıklamayı dener.
  /// Desteklenen formatlar:
  /// dd.MM.yyyy, dd/MM/yyyy, dd-MM-yyyy, dd.MM.yy, MM.yyyy (sadece ay/yıl)
  static DateTime? parseFromOcr(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');

    // dd[./-]MM[./-]yyyy  veya  dd[./-]MM[./-]yy
    final full = RegExp(r'(\d{1,2})[./\-](\d{1,2})[./\-](\d{2,4})');
    for (final m in full.allMatches(normalized)) {
      final d = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      var y = int.tryParse(m.group(3)!);
      if (d == null || mo == null || y == null) continue;
      if (y < 100) y += 2000; // 25 -> 2025
      final dt = _safeDate(y, mo, d);
      if (dt != null) return dt;
    }

    // MM[./-]yyyy  (sadece ay/yıl -> ayın son günü)
    final monthYear = RegExp(r'(?<!\d)(\d{1,2})[./\-](\d{4})(?!\d)');
    for (final m in monthYear.allMatches(normalized)) {
      final mo = int.tryParse(m.group(1)!);
      final y = int.tryParse(m.group(2)!);
      if (mo == null || y == null || mo < 1 || mo > 12) continue;
      final lastDay = DateTime(y, mo + 1, 0).day;
      final dt = _safeDate(y, mo, lastDay);
      if (dt != null) return dt;
    }

    return null;
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (year < 2000 || year > 2100) return null;
    final dt = DateTime(year, month, day);
    // Geçersiz gün (ör. 31 Şubat) DateTime tarafından kaydırılır; doğrula.
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  }
}
