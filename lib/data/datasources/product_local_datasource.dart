import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/product.dart';

/// Ürünler için yerel (SQLite) veri kaynağı.
class ProductLocalDataSource {
  final DatabaseService _dbService;
  ProductLocalDataSource(this._dbService);

  /// Sadece aktif urunler (disposal_status = active).
  Future<List<Product>> getActive() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.productTable,
      where: "disposal_status = 'active'",
      orderBy: 'expiry_date ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Imha ve iade gecmisi - son 90 gun.
  Future<List<Product>> getDisposalHistory() async {
    final db = await _dbService.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: AppConstants.disposalHistoryDays))
        .millisecondsSinceEpoch;
    final rows = await db.query(
      AppConstants.productTable,
      where: "disposal_status != 'active' AND disposal_date >= ?",
      whereArgs: [cutoff],
      orderBy: 'disposal_date DESC',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Ayni barkoda ait TUM aktif partileri dondurur (farkli SKT'li stoklar).
  Future<List<Product>> getAllActiveByBarcode(String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.productTable,
      where: "barcode = ? AND disposal_status = 'active'",
      whereArgs: [barcode],
      orderBy: 'expiry_date ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// Barkoda gore EN SON eklenen aktif urunu dondurur.
  /// Ayni barkodla birden fazla aktif parti olabilir (farkli SKT);
  /// duzenleme/on-doldurma icin en guncel olani secilir.
  /// Bu barkodla kayitli TUM aktif SKT urunleri — en yakin tarih once.
  /// Barkod detay sayfasinda "tanimli SKT var mi" gostermek icin.
  Future<List<Product>> getActiveListByBarcode(String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.productTable,
      where: "barcode = ? AND disposal_status = 'active'",
      whereArgs: [barcode],
      orderBy: 'expiry_date ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// KALICI BAGLI urunlerin konum etiketleri (tek sorguda):
  /// pallet -> 'Palet <kod>', shelf -> '<reyon adi>'. id -> etiket.
  Future<Map<int, String>> getLinkedLocationLabels() async {
    final db = await _dbService.database;
    final out = <int, String>{};
    try {
      final pr = await db.rawQuery(
          "SELECT p.id AS pid, wp.code AS label FROM ${AppConstants.productTable} p "
          "JOIN ${AppConstants.whPalletItemTable} i ON p.location_ref = i.id "
          "JOIN ${AppConstants.whPalletTable} wp ON i.pallet_id = wp.id "
          "WHERE p.location_type = 'pallet' AND p.disposal_status = 'active'");
      for (final r in pr) {
        final id = r['pid'] as int?;
        final lb = r['label'] as String?;
        if (id != null && lb != null) out[id] = 'Palet $lb';
      }
      final sr = await db.rawQuery(
          "SELECT p.id AS pid, su.name AS label FROM ${AppConstants.productTable} p "
          "JOIN ${AppConstants.shelfSlotTable} ss ON p.location_ref = ss.id "
          "JOIN ${AppConstants.shelfUnitTable} su ON ss.unit_id = su.id "
          "WHERE p.location_type = 'shelf' AND p.disposal_status = 'active'");
      for (final r in sr) {
        final id = r['pid'] as int?;
        final lb = r['label'] as String?;
        if (id != null && lb != null) out[id] = lb;
      }
    } catch (_) {}
    return out;
  }

  Future<Product?> getByBarcode(String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.productTable,
      where: "barcode = ? AND disposal_status = 'active'",
      whereArgs: [barcode],
      orderBy: 'created_at DESC',
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
    for (final p in products) {
      batch.insert(AppConstants.productTable, p.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// 90 gun gecmis imha/iade kayitlarini temizle.
  Future<void> purgeOldDisposals() async {
    final db = await _dbService.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: AppConstants.disposalHistoryDays))
        .millisecondsSinceEpoch;
    await db.delete(
      AppConstants.productTable,
      where: "disposal_status != 'active' AND disposal_date < ?",
      whereArgs: [cutoff],
    );
  }
}
