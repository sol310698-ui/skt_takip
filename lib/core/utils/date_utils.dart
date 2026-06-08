import '../constants/app_constants.dart';

/// Tarih hesaplama ve OCR metninden tarih ayiklama yardimcilari.
class DateUtils {
  DateUtils._();

  static int daysUntil(DateTime expiry) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(expiry.year, expiry.month, expiry.day);
    return target.difference(today).inDays;
  }

  static ExpiryStatus statusFor(DateTime expiry) {
    final days = daysUntil(expiry);
    if (days < 0) return ExpiryStatus.expired;
    if (days <= AppConstants.criticalDays) return ExpiryStatus.critical;
    if (days <= AppConstants.warningDays) return ExpiryStatus.warning;
    return ExpiryStatus.safe;
  }

  /// OCR metninden SON KULLANMA tarihini akilli sekilde ayiklar.
  /// - Anahtar kelime tanir (SKT/STT/SON = son kullanma, UT/URETIM = uretim)
  /// - Esnek ayrac: nokta, slash, tire, bosluk, iki nokta, ayracsiz
  /// - Harf->rakam duzeltir (O->0, I->1, S->5, B->8, Z->2)
  /// - 2 haneli yili 2000'e tamamlar
  /// - Iki tarih varsa son kullanmayi (uretim degil) secer
  static DateTime? parseFromOcr(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));

    // 1) Once "son kullanma" anahtar kelimesi olan satiri ara.
    final expiryKeywords = RegExp(
      r'(S\.?K\.?T|S\.?T\.?T|SON\s*T|T\.?E\.?T\.?T?|TUK|TÜK|EXP|BBE|USE\s*BY|LAST)',
      caseSensitive: false,
    );
    final productionKeywords = RegExp(
      r'(Ü\.?T|U\.?T|ÜRT|URT|ÜRET|URET|IMAL|İMAL|PROD|MFG|ÜRETİM|URETIM)',
      caseSensitive: false,
    );

    // Once son kullanma satirlarini dene
    for (final line in lines) {
      if (expiryKeywords.hasMatch(line)) {
        final d = _extractDate(line);
        if (d != null) return d;
      }
    }

    // 2) Anahtar kelime eslesmediyse: uretim OLMAYAN satirlardaki tarihleri topla
    final candidates = <DateTime>[];
    for (final line in lines) {
      if (productionKeywords.hasMatch(line)) continue; // uretimi atla
      final d = _extractDate(line);
      if (d != null) candidates.add(d);
    }
    if (candidates.isNotEmpty) {
      // En ileri (gec) tarih son kullanmadir.
      candidates.sort((a, b) => b.compareTo(a));
      return candidates.first;
    }

    // 3) Hicbiri olmazsa tum metinde en gec tarihi bul
    final all = _extractAllDates(text);
    if (all.isNotEmpty) {
      all.sort((a, b) => b.compareTo(a));
      return all.first;
    }

    return null;
  }

  /// Harfe benzeyen rakamlari duzeltir (noktali matris baski hatalari).
  static String _fixOcrDigits(String s) {
    return s
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[Iil|]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5')
        .replaceAll(RegExp(r'[Bb]'), '8')
        .replaceAll(RegExp(r'[Zz]'), '2');
  }

  /// Bir satirdan tek tarih ayiklar.
  static DateTime? _extractDate(String line) {
    final dates = _extractAllDates(line);
    return dates.isEmpty ? null : dates.first;
  }

  /// Bir metinden tum gecerli tarihleri ayiklar.
  /// Desteklenen ayraclar: . / - : bosluk ve ayracsiz (6/8 hane).
  static List<DateTime> _extractAllDates(String text) {
    final results = <DateTime>[];

    // Ayracli format: gun[ayrac]ay[ayrac]yil
    // Ayraclar: . / - : ve bosluk (bir veya daha fazla)
    final sep = RegExp(
      r'(\d{1,2})\s*[.\-/: ]\s*(\d{1,2})\s*[.\-/: ]\s*(\d{2,4})',
    );
    for (final m in sep.allMatches(text)) {
      final d = _build(m.group(1), m.group(2), m.group(3));
      if (d != null) results.add(d);
    }

    // Ayracsiz bitisik: ddMMyy (6 hane) veya ddMMyyyy (8 hane)
    final compact = RegExp(r'(?<!\d)(\d{6}|\d{8})(?!\d)');
    for (final m in compact.allMatches(text)) {
      final raw = m.group(1)!;
      String dd, mm, yy;
      if (raw.length == 6) {
        dd = raw.substring(0, 2);
        mm = raw.substring(2, 4);
        yy = raw.substring(4, 6);
      } else {
        dd = raw.substring(0, 2);
        mm = raw.substring(2, 4);
        yy = raw.substring(4, 8);
      }
      final d = _build(dd, mm, yy);
      if (d != null) results.add(d);
    }

    return results;
  }

  /// gun/ay/yil parcalarini gecerli DateTime'a cevirir.
  static DateTime? _build(String? dStr, String? mStr, String? yStr) {
    if (dStr == null || mStr == null || yStr == null) return null;

    int? day = int.tryParse(_fixOcrDigits(dStr));
    int? month = int.tryParse(_fixOcrDigits(mStr));
    int? year = int.tryParse(_fixOcrDigits(yStr));
    if (day == null || month == null || year == null) return null;

    // 2 haneli yili tamamla
    if (year < 100) year += 2000;

    // Gun/ay karismasi: biri 12'den buyukse o kesin gun.
    if (month > 12 && day <= 12) {
      final t = day;
      day = month;
      month = t;
    }

    return _safeDate(year, month, day);
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (year < 2020 || year > 2100) return null;
    final dt = DateTime(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) return null;
    return dt;
  }
}
