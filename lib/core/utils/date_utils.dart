import '../constants/app_constants.dart';

/// Tarih hesaplama ve OCR metninden AKILLI tarih ayiklama.
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

  // Son kullanma anahtar kelimeleri (genis liste)
  static final RegExp _expiryKw = RegExp(
    r'(S\.?K\.?T|S\.?T\.?T|SON\s*T[UÜ]K|SON\s*KUL|T\.?E\.?T\.?[Tİ]?|TUK|TÜK|EXP|BBE|USE\s*BY|LAST|TET[Tİ])',
    caseSensitive: false,
  );

  // Uretim anahtar kelimeleri (bunlari ATLA)
  static final RegExp _productionKw = RegExp(
    r'(Ü\.?T|U\.?T|ÜRT|URT|ÜRET|URET|IMAL|İMAL|PROD|MFG|ÜRETİM|URETIM|PRODUCTION)',
    caseSensitive: false,
  );

  /// ANA FONKSIYON: OCR metninden son kullanma tarihini akilli secer.
  /// Tum tarih adaylarini bulur, guven skoru verir, en iyisini dondurur.
  static DateTime? parseFromOcr(String text) {
    final candidates = _collectCandidates(text);
    if (candidates.isEmpty) return null;

    // En yuksek skorlu adayi sec.
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.date;
  }

  /// Tum tarih adaylarini skorlariyla dondurur (UX'te aday secimi icin).
  static List<DateCandidate> parseAllCandidates(String text) {
    final candidates = _collectCandidates(text);
    candidates.sort((a, b) => b.score.compareTo(a.score));
    // Ayni tarihleri tekille
    final seen = <String>{};
    final unique = <DateCandidate>[];
    for (final c in candidates) {
      final key = '${c.date.year}-${c.date.month}-${c.date.day}';
      if (seen.add(key)) unique.add(c);
    }
    return unique;
  }

  /// Birden fazla OCR metnini (coklu preprocessing) birlestirip en iyi tarihi secer.
  /// Coklu versiyondan ayni tarih cikarsa guveni artar (oylama).
  static DateTime? parseFromMultiple(List<String> texts) {
    final allCandidates = <DateCandidate>[];
    for (final t in texts) {
      allCandidates.addAll(_collectCandidates(t));
    }
    if (allCandidates.isEmpty) return null;

    // Ayni tarihleri grupla, tekrar sayisini skora ekle (oylama).
    final Map<String, DateCandidate> grouped = {};
    for (final c in allCandidates) {
      final key = '${c.date.year}-${c.date.month}-${c.date.day}';
      if (grouped.containsKey(key)) {
        grouped[key] = grouped[key]!.copyWith(
          score: grouped[key]!.score + c.score + 20, // tekrar bonusu
        );
      } else {
        grouped[key] = c;
      }
    }

    final list = grouped.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.first.date;
  }

  /// Metinden tum tarih adaylarini skorlariyla toplar.
  static List<DateCandidate> _collectCandidates(String text) {
    final candidates = <DateCandidate>[];
    final lines = text.split(RegExp(r'[\r\n]+'));

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isProduction = _productionKw.hasMatch(line);
      final isExpiry = _expiryKw.hasMatch(line);

      // Bu satirdaki tum tarihleri bul
      final dates = _extractDatesFromLine(line);
      for (final d in dates) {
        int score = _baseScore(d);

        // Anahtar kelime bonusu/cezasi
        if (isExpiry) score += 50;       // son kullanma satiri
        if (isProduction) score -= 40;   // uretim satiri (istemiyoruz)

        candidates.add(DateCandidate(date: d, score: score, sourceLine: line));
      }
    }

    return candidates;
  }

  /// Bir tarihin temel guven skoru (anahtar kelimeden bagimsiz).
  static int _baseScore(DateTime d) {
    int score = 0;
    final days = daysUntil(d);

    // Gelecekteki tarih = muhtemelen SKT (en guclu sinyal)
    if (days >= 0) {
      score += 30;
      // Makul SKT araligi: bugun + 1 gun ... bugun + 3 yil
      if (days <= 365 * 3) score += 20;
    } else {
      // Gecmis tarih: hafif gecmis olabilir (yeni dolmus urun)
      if (days >= -90) {
        score += 5; // son 3 ayda dolmus, olabilir
      } else {
        score -= 20; // cok eski, muhtemelen uretim tarihi
      }
    }

    // Cok ileri tarih (10 yildan fazla) supheli
    if (days > 365 * 10) score -= 30;

    return score;
  }

  /// Harfe benzeyen rakamlari duzeltir (noktali/lazer baski hatalari).
  static String _fixOcrDigits(String s) {
    return s
        .replaceAll(RegExp(r'[Oo]'), '0')
        .replaceAll(RegExp(r'[Il|]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5')
        .replaceAll(RegExp(r'[Bb]'), '8')
        .replaceAll(RegExp(r'[Zz]'), '2')
        .replaceAll(RegExp(r'[gqG]'), '9');
  }

  /// Bir satirdan tum gecerli tarihleri ayiklar.
  static List<DateTime> _extractDatesFromLine(String line) {
    final results = <DateTime>[];

    // 1) Tam tarih: gun[ayrac]ay[ayrac]yil
    // Ayraclar: . / - : bosluk
    final full = RegExp(
      r'(\d{1,2})\s*[.\-/: ]\s*(\d{1,2})\s*[.\-/: ]\s*(\d{2,4})',
    );
    for (final m in full.allMatches(line)) {
      final d = _buildFull(m.group(1), m.group(2), m.group(3));
      if (d != null) results.add(d);
    }

    // 2) Ay-yil: ay[ayrac]yil (gun yok) - orn 02.2027, 07/26
    // Sadece tam tarih bulunamadiysa dene (cakismayi onle)
    if (results.isEmpty) {
      final monthYear = RegExp(r'(\d{1,2})\s*[.\-/]\s*(\d{4}|\d{2})');
      for (final m in monthYear.allMatches(line)) {
        final d = _buildMonthYear(m.group(1), m.group(2));
        if (d != null) results.add(d);
      }
    }

    // 3) Ayracsiz bitisik: ddMMyy (6) veya ddMMyyyy (8)
    final compact = RegExp(r'(?<!\d)(\d{6}|\d{8})(?!\d)');
    for (final m in compact.allMatches(line)) {
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
      final d = _buildFull(dd, mm, yy);
      if (d != null) results.add(d);
    }

    return results;
  }

  /// gun/ay/yil -> DateTime
  static DateTime? _buildFull(String? dStr, String? mStr, String? yStr) {
    if (dStr == null || mStr == null || yStr == null) return null;
    int? day = int.tryParse(_fixOcrDigits(dStr));
    int? month = int.tryParse(_fixOcrDigits(mStr));
    int? year = int.tryParse(_fixOcrDigits(yStr));
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;

    // Gun/ay karismasi: biri 12'den buyukse o gundur.
    if (month > 12 && day <= 12) {
      final t = day;
      day = month;
      month = t;
    }
    return _safeDate(year, month, day);
  }

  /// ay/yil -> ayin son gunu (SKT genelde ay sonu kabul edilir)
  static DateTime? _buildMonthYear(String? mStr, String? yStr) {
    if (mStr == null || yStr == null) return null;
    int? month = int.tryParse(_fixOcrDigits(mStr));
    int? year = int.tryParse(_fixOcrDigits(yStr));
    if (month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12) return null;
    if (year < 2020 || year > 2100) return null;
    // Ayin son gunu
    final lastDay = DateTime(year, month + 1, 0).day;
    return _safeDate(year, month, lastDay);
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

/// Tarih adayi + guven skoru.
class DateCandidate {
  final DateTime date;
  final int score;
  final String sourceLine;

  const DateCandidate({
    required this.date,
    required this.score,
    this.sourceLine = '',
  });

  DateCandidate copyWith({DateTime? date, int? score, String? sourceLine}) {
    return DateCandidate(
      date: date ?? this.date,
      score: score ?? this.score,
      sourceLine: sourceLine ?? this.sourceLine,
    );
  }

  /// Guven seviyesi (UX icin): yuksek/orta/dusuk
  String get confidenceLabel {
    if (score >= 80) return 'yuksek';
    if (score >= 40) return 'orta';
    return 'dusuk';
  }
}
