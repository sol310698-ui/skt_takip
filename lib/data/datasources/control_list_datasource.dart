import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/control_list_item.dart';

/// Yonetici kontrol listesi yerel veri kaynagi.
class ControlListDataSource {
  final DatabaseService _dbService;
  ControlListDataSource(this._dbService);

  /// Yeni bir liste yukle. replaceAll=true ise once mevcut liste silinir
  /// (yeni bir Excel/foto geldiginde eskisini degistirir); false ise
  /// mevcut listenin sonuna eklenir (birden fazla foto birlestirilebilir).
  Future<int> insertItems(List<ControlListItem> items,
      {bool replaceAll = false}) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete(AppConstants.controlListTable);
      }
      for (final item in items) {
        final map = item.toMap()..remove('id');
        await txn.insert(AppConstants.controlListTable, map);
      }
    });
    return items.length;
  }

  Future<List<ControlListItem>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.controlListTable,
      orderBy: 'id ASC',
    );
    return rows.map(ControlListItem.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _dbService.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) as c FROM ${AppConstants.controlListTable}');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> setChecked(int id, bool checked) async {
    final db = await _dbService.database;
    await db.update(
      AppConstants.controlListTable,
      {'checked': checked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteById(int id) async {
    final db = await _dbService.database;
    await db.delete(
      AppConstants.controlListTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await _dbService.database;
    await db.delete(AppConstants.controlListTable);
  }
}
