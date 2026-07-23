import '../../core/constants/app_constants.dart';
import '../../data/models/label_pending_item.dart';
import 'database_service.dart';

/// Baska ekranlardan (orn. Fiyat Degisim) Etiket Basim'a urun gondermek
/// icin kullanilan kuyruk. Etiket Basim ekrani acildiginda [drainAll]
/// cagrilir: kuyruktaki tum kayitlar okunur ve kuyruk bosaltilir.
class LabelPendingQueueService {
  LabelPendingQueueService._();
  static final LabelPendingQueueService instance =
      LabelPendingQueueService._();

  /// Baska bir ekrandan urun gonderir (kuyruga ekler).
  Future<void> push({
    required String barcode,
    required String productName,
    String? stockCode,
    required String groupKey,
    int quantity = 1,
    required String source,
  }) async {
    final db = await DatabaseService.instance.database;
    final item = LabelPendingItem(
      barcode: barcode,
      productName: productName,
      stockCode: stockCode,
      groupKey: groupKey,
      quantity: quantity,
      source: source,
      addedAt: DateTime.now(),
    );
    await db.insert(AppConstants.labelPendingQueueTable, item.toMap());
  }

  /// Kuyruktaki tum kayitlari doner ve kuyrugu bosaltir.
  /// Etiket Basim ekrani acilirken cagrilmalidir.
  Future<List<LabelPendingItem>> drainAll() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.labelPendingQueueTable,
      orderBy: 'added_at ASC',
    );
    if (rows.isEmpty) return [];
    await db.delete(AppConstants.labelPendingQueueTable);
    return rows.map(LabelPendingItem.fromMap).toList();
  }

  /// GRUP BAZINDA bekleyen sayilari (etiket hedefi secerken gosterilir):
  /// {'a4': 3, 'kalinRon': 1, ...}
  Future<Map<String, int>> pendingCountsByGroup() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(
        'SELECT group_key, COUNT(*) c FROM '
        '${AppConstants.labelPendingQueueTable} GROUP BY group_key');
    final out = <String, int>{};
    for (final r in rows) {
      final k = (r['group_key'] ?? '').toString();
      if (k.isEmpty) continue;
      out[k] = (r['c'] as int?) ?? 0;
    }
    return out;
  }

  /// Kuyrukta bekleyen kayit var mi (rozet/bildirim icin).
  Future<int> pendingCount() async {
    final db = await DatabaseService.instance.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as c FROM ${AppConstants.labelPendingQueueTable}');
    return (result.first['c'] as int?) ?? 0;
  }
}
