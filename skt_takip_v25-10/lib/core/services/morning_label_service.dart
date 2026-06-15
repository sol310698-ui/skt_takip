import '../constants/app_constants.dart';
import 'database_service.dart';

/// Sabah etiket kaydi: teslim alinan etiketlerin barkod+fiyat kaydi.
class MorningLabel {
  final int? id;
  final String barcode;
  final double? price;
  final DateTime? labelExpiry;
  final DateTime? labelPrint;
  final DateTime scannedAt;
  final String? a4Photo;

  const MorningLabel({
    this.id,
    required this.barcode,
    this.price,
    this.labelExpiry,
    this.labelPrint,
    required this.scannedAt,
    this.a4Photo,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'barcode': barcode,
        'price': price,
        'label_expiry': labelExpiry?.millisecondsSinceEpoch,
        'label_print': labelPrint?.millisecondsSinceEpoch,
        'scanned_at': scannedAt.millisecondsSinceEpoch,
        'a4_photo': a4Photo,
      };

  factory MorningLabel.fromMap(Map<String, Object?> m) => MorningLabel(
        id: m['id'] as int?,
        barcode: m['barcode'] as String,
        price: (m['price'] as num?)?.toDouble(),
        labelExpiry: m['label_expiry'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['label_expiry'] as int)
            : null,
        labelPrint: m['label_print'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['label_print'] as int)
            : null,
        scannedAt:
            DateTime.fromMillisecondsSinceEpoch(m['scanned_at'] as int),
        a4Photo: m['a4_photo'] as String?,
      );
}

/// Sorgu sonucu: kayit + fiyat farki bilgisi.
class MorningQueryResult {
  final MorningLabel record;
  final double? currentPrice; // sorgulanan etiketteki fiyat
  const MorningQueryResult({required this.record, this.currentPrice});

  /// Fiyat degisti mi? (kayitli fiyat ile sorgulanan fiyat farkli)
  bool get priceChanged =>
      currentPrice != null &&
      record.price != null &&
      (currentPrice! - record.price!).abs() > 0.001;
}

/// Sabah etiket kayit servisi (30 gun saklama).
class MorningLabelService {
  MorningLabelService._();
  static final MorningLabelService instance = MorningLabelService._();

  /// Yeni etiket kaydi ekler.
  Future<void> add(MorningLabel label) async {
    final db = await DatabaseService.instance.database;
    await db.insert(
        AppConstants.morningLabelTable, label.toMap()..remove('id'));
  }

  /// Barkodu son 30 gunde ara. En guncel kaydi dondurur.
  Future<MorningLabel?> findByBarcode(String barcode) async {
    final db = await DatabaseService.instance.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      AppConstants.morningLabelTable,
      where: 'barcode = ? AND scanned_at >= ?',
      whereArgs: [barcode.trim(), cutoff],
      orderBy: 'scanned_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MorningLabel.fromMap(rows.first);
  }

  /// Bugunku kayitlari dondurur (oturum listesi icin).
  Future<List<MorningLabel>> getToday() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();
    final startOfDay =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await db.query(
      AppConstants.morningLabelTable,
      where: 'scanned_at >= ?',
      whereArgs: [startOfDay],
      orderBy: 'scanned_at DESC',
    );
    return rows.map(MorningLabel.fromMap).toList();
  }


  /// Son 30 günün tüm kayıtlarını döndürür, en yeni önce.
  Future<List<MorningLabel>> getLast30Days() async {
    final db = await DatabaseService.instance.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      AppConstants.morningLabelTable,
      where: 'scanned_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'scanned_at DESC',
    );
    return rows.map(MorningLabel.fromMap).toList();
  }


  /// Tek kaydı id ile siler.
  Future<void> deleteById(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(
      AppConstants.morningLabelTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Belirli bir günün tüm kayıtlarını siler.
  Future<void> deleteDay(DateTime day) async {
    final db = await DatabaseService.instance.database;
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final end   = DateTime(day.year, day.month, day.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    await db.delete(
      AppConstants.morningLabelTable,
      where: 'scanned_at >= ? AND scanned_at <= ?',
      whereArgs: [start, end],
    );
  }

  /// Son 30 günün tüm kayıtlarını siler.
  Future<void> deleteAll() async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.morningLabelTable);
  }

  /// 30 gunden eski kayitlari temizler.
  Future<void> purgeOld() async {
    final db = await DatabaseService.instance.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await db.delete(
      AppConstants.morningLabelTable,
      where: 'scanned_at < ?',
      whereArgs: [cutoff],
    );
  }
}
