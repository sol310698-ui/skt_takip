import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/product.dart';

/// Ürünler için yerel (SQLite) veri kaynağı.
class ProductLocalDataSource {
  final DatabaseService _dbService;

  ProductLocalDataSource(this._dbService);

  Future<List<Product>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.productTable,
      orderBy: 'expiry_date ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getByBarcode(String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.productTable,
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<int> insert(Product product) async {
    final db = await _dbService.database;
    return db.insert(AppConstants.productTable, product.toMap());
  }

  Future<int> update(Product product) async {
    final db = await _dbService.database;
    return db.update(
      AppConstants.productTable,
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _dbService.database;
    return db.delete(
      AppConstants.productTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertAll(List<Product> products) async {
    final db = await _dbService.database;
    final batch = db.batch();
    for (final product in products) {
      batch.insert(AppConstants.productTable, product.toMap());
    }
    await batch.commit(noResult: true);
  }
}
