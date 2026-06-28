import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/count_item.dart';

/// Bagimsiz sayim verisi (count_items tablosu).
class CountDataSource {
  final DatabaseService _dbService;
  CountDataSource(this._dbService);

  /// Tum sayim kayitlari (en yeni ustte).
  Future<List<CountItem>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.countTable,
      orderBy: 'counted_at DESC',
    );
    return rows.map((r) => CountItem.fromMap(r)).toList();
  }

  /// Bu barkod daha once sayildi mi? (varsa kaydini dondurur)
  Future<CountItem?> findByBarcode(String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.countTable,
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CountItem.fromMap(rows.first);
  }

  /// Yeni sayim ekle, eklenen id'yi dondur.
  Future<int> insert(CountItem item) async {
    final db = await _dbService.database;
    final map = item.toMap()..remove('id');
    return db.insert(AppConstants.countTable, map);
  }

  /// Mevcut sayimin adedini guncelle.
  Future<void> updateQty(int id, int qty) async {
    final db = await _dbService.database;
    await db.update(
      AppConstants.countTable,
      {'qty': qty, 'counted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteById(int id) async {
    final db = await _dbService.database;
    await db.delete(AppConstants.countTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await _dbService.database;
    await db.delete(AppConstants.countTable);
  }
}
