import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/barcode_entry.dart';

/// Barkod dizini (Excel import) icin yerel veri kaynagi.
class BarcodeDirectoryDataSource {
  final DatabaseService _dbService;
  BarcodeDirectoryDataSource(this._dbService);

  /// Barkod ile urun adi sorgula.
  Future<String?> findProductName(String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.barcodeTable,
      columns: ['product_name'],
      where: 'barcode = ?',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['product_name'] as String;
  }

  /// Toplu import - varsa uzerine yazar (UPSERT).
  Future<int> importAll(List<BarcodeEntry> entries) async {
    final db = await _dbService.database;
    final batch = db.batch();
    for (final e in entries) {
      batch.insert(
        AppConstants.barcodeTable,
        e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return entries.length;
  }

  Future<List<BarcodeEntry>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.barcodeTable,
      orderBy: 'imported_at DESC',
    );
    return rows.map(BarcodeEntry.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _dbService.database;
    final result = await db
        .rawQuery('SELECT COUNT(*) as c FROM ${AppConstants.barcodeTable}');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> clearAll() async {
    final db = await _dbService.database;
    await db.delete(AppConstants.barcodeTable);
  }

  /// Tekil kayit sil (id ile).
  Future<void> deleteById(int id) async {
    final db = await _dbService.database;
    await db.delete(
      AppConstants.barcodeTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ayni urun adi VEYA benzer barkod sayisi (silme uyarisi icin).
  /// Verilen kaydin disindaki eslesmeleri sayar.
  Future<int> countSimilar({
    required int excludeId,
    required String productName,
    required String barcode,
  }) async {
    final db = await _dbService.database;
    // Ayni ad VEYA ilk 8 hanesi ayni barkod (ayni urun ailesi)
    final prefix =
        barcode.length >= 8 ? barcode.substring(0, 8) : barcode;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as c FROM ${AppConstants.barcodeTable}
      WHERE id != ? AND (product_name = ? OR barcode LIKE ?)
      ''',
      [excludeId, productName, '$prefix%'],
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
