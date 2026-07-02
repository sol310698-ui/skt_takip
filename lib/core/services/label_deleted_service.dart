import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../data/models/label_item.dart';
import 'database_service.dart';

/// Silinen bir etiket partisi (ayni anda silinen etiketler grubu).
class DeletedBatch {
  final String batchId;
  final String groupKey;
  final DateTime deletedAt;
  final List<LabelItem> items;

  DeletedBatch({
    required this.batchId,
    required this.groupKey,
    required this.deletedAt,
    required this.items,
  });
}

/// Etiket Basim'da SILINEN etiketleri KALICI saklar; parti (batch) halinde
/// geri almayi saglar. Her silme islemi (tekil, coklu, tumunu-sil) bir
/// batch_id ile gruplanir; "Silinenler" sayfasindan bir parti tek tusla
/// geri yuklenebilir.
class LabelDeletedService {
  LabelDeletedService._();
  static final LabelDeletedService instance = LabelDeletedService._();

  /// Silinen etiketleri bir PARTI olarak kaydet. Ayni batchId ile cagrilan
  /// etiketler tek grup olur. Geri donen deger batchId'dir.
  Future<String> recordBatch(String groupKey, List<LabelItem> items) async {
    final db = await DatabaseService.instance.database;
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(AppConstants.labelDeletedTable, {
        'batch_id': batchId,
        'group_key': groupKey,
        'item_json': jsonEncode(item.toJson()),
        'deleted_at': now,
      });
    }
    await batch.commit(noResult: true);
    return batchId;
  }

  /// Tum silinen partileri (en yeni ustte) dondurur.
  Future<List<DeletedBatch>> loadBatches() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.labelDeletedTable,
      orderBy: 'deleted_at DESC, id DESC',
    );
    // batch_id'ye gore grupla.
    final map = <String, DeletedBatch>{};
    for (final row in rows) {
      final batchId = row['batch_id'] as String;
      final groupKey = row['group_key'] as String;
      final deletedAt =
          DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int);
      LabelItem? item;
      try {
        item = LabelItem.fromJson(
            jsonDecode(row['item_json'] as String) as Map<String, Object?>);
      } catch (_) {
        item = null;
      }
      if (item == null) continue;
      final existing = map[batchId];
      if (existing == null) {
        map[batchId] = DeletedBatch(
          batchId: batchId,
          groupKey: groupKey,
          deletedAt: deletedAt,
          items: [item],
        );
      } else {
        existing.items.add(item);
      }
    }
    return map.values.toList();
  }

  /// Bir partinin etiketlerini dondurur (geri yuklemek icin) ve silinenler
  /// tablosundan kaldirir.
  Future<List<LabelItem>> restoreBatch(String batchId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.labelDeletedTable,
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
    final items = <LabelItem>[];
    for (final row in rows) {
      try {
        items.add(LabelItem.fromJson(
            jsonDecode(row['item_json'] as String) as Map<String, Object?>));
      } catch (_) {}
    }
    await db.delete(
      AppConstants.labelDeletedTable,
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
    return items;
  }

  /// Bir partiyi kalici olarak sil (geri alinamaz).
  Future<void> deleteBatch(String batchId) async {
    final db = await DatabaseService.instance.database;
    await db.delete(
      AppConstants.labelDeletedTable,
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
  }

  /// Tum silinenler gecmisini temizle.
  Future<void> clearAll() async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.labelDeletedTable);
  }
}
