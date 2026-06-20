import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/label_history_entry.dart';
import 'database_service.dart';

/// Etiket Basım ekranında listeye eklenen barkodların 30 günlük
/// kalıcı geçmişini tutan servis. Aktif liste (LabelPrintScreen state'i)
/// ile bu geçmiş BİRBİRİNDEN BAĞIMSIZDIR: aktif liste sıfırlansa/akış
/// bitse bile buradaki kayıtlar 30 gün boyunca durur.
class LabelHistoryService {
  LabelHistoryService._();
  static final LabelHistoryService instance = LabelHistoryService._();

  /// Bir barkod listeye eklendiğinde / adedi arttığında çağrılır.
  /// Her ekleme ayrı bir satır olarak loglanır (adet o anki eklenen miktar).
  Future<void> log({
    required String barcode,
    required String productName,
    String? stockCode,
    required String groupKey,
    required String groupTitle,
    int quantity = 1,
  }) async {
    final db = await DatabaseService.instance.database;
    final entry = LabelHistoryEntry(
      barcode: barcode,
      productName: productName,
      stockCode: stockCode,
      groupKey: groupKey,
      groupTitle: groupTitle,
      quantity: quantity,
      addedAt: DateTime.now(),
    );
    await db.insert(AppConstants.labelHistoryTable, entry.toMap());
    // Fırsat buldukça eski kayıtları temizle (her log'da maliyetsiz).
    await _purgeOld(db);
  }

  /// Son [days] güne ait kayıtları, en yeniden eskiye sıralı döner.
  Future<List<LabelHistoryEntry>> getRecent({int days = 30}) async {
    final db = await DatabaseService.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      AppConstants.labelHistoryTable,
      where: 'added_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'added_at DESC',
    );
    return rows.map(LabelHistoryEntry.fromMap).toList();
  }

  Future<void> _purgeOld(Database db) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: AppConstants.labelHistoryDays))
        .millisecondsSinceEpoch;
    await db.delete(
      AppConstants.labelHistoryTable,
      where: 'added_at < ?',
      whereArgs: [cutoff],
    );
  }

  /// Geçmişi tamamen temizle (kullanıcı isterse manuel).
  Future<void> clearAll() async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.labelHistoryTable);
  }
}
