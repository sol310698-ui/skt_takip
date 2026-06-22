import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/barcode_entry.dart';

/// Barkod dizini (Excel import) icin yerel veri kaynagi.
class BarcodeDirectoryDataSource {
  final DatabaseService _dbService;
  BarcodeDirectoryDataSource(this._dbService);

  /// Barkod ile tam BarcodeEntry dondurur (id dahil, silme icin gerekli).
  /// SQL tarafinda TRIM kullanilir: Excel'den gelen kayitlarda olusabilecek
  /// bas/son bosluklarina karsi dayanikli arama.
  Future<BarcodeEntry?> findEntryByBarcode(String barcode) async {
    final db = await _dbService.database;
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final rows = await db.query(
      AppConstants.barcodeTable,
      where: 'TRIM(barcode) = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BarcodeEntry.fromMap(rows.first);
  }

  /// Stok kodu ile tam BarcodeEntry dondurur (etiket/raf akisinda kullanilir).
  Future<BarcodeEntry?> findEntryByStockCode(String stockCode) async {
    final db = await _dbService.database;
    final code = stockCode.trim();
    if (code.isEmpty) return null;
    final rows = await db.query(
      AppConstants.barcodeTable,
      where: 'TRIM(stock_code) = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BarcodeEntry.fromMap(rows.first);
  }

  /// Barkod ile urun adi sorgula.
  Future<String?> findProductName(String barcode) async {
    final db = await _dbService.database;
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final rows = await db.query(
      AppConstants.barcodeTable,
      columns: ['product_name'],
      where: 'TRIM(barcode) = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['product_name'] as String;
  }

  /// Toplu import - varsa uzerine yazar (UPSERT, barkod UNIQUE uzerinden).
  ///
  /// VERI ONCELIGI (kaynak bazli):
  ///   excel(4) > manual(3) > scan(2) > off/internet(1) > unknown(0)
  /// Excel'den gelen veriler EN GUVENILIR kabul edilir ve her zaman digerlerinin
  /// uzerine yazar. Dusuk oncelikli bir kaynak (ornegin internet/off), mevcut
  /// daha yuksek oncelikli bir kaydin urun adini/stok kodunu EZEMEZ.
  ///
  /// Kurallar:
  ///  - Barkod yoksa: yeni kayit eklenir (kaynak ne ise o).
  ///  - Barkod varsa:
  ///     * Gelen kaynak >= mevcut kaynak ise: urun adi + kaynak guncellenir.
  ///       (Excel her zaman gunceller.)
  ///     * Gelen kaynak < mevcut kaynak ise: urun adi/kaynak KORUNUR
  ///       (internet, Excel verisini bozmaz).
  ///  - Stok kodu: gelen kayitta DOLU ise ve (gelen kaynak >= mevcut kaynak)
  ///    ise yazilir; aksi halde mevcut stok kodu KORUNUR (asla bos ile silinmez).
  /// [forceOverwrite] true ise: gelen kaydin urun adi (ve dolu ise stok
  /// kodu) kaynak onceligine BAKILMAKSIZIN mevcut kaydin uzerine yazilir.
  /// Bu, kullanicinin etiket kagidindan ELLE girdigi durum icindir — en
  /// guncel/dogru tanim odur, Excel kaydinin bile uzerine yazar.
  /// false (varsayilan) ise eski oncelik mantigi gecerlidir (Excel korunur).
  Future<int> importAll(List<BarcodeEntry> entries,
      {bool forceOverwrite = false}) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final e in entries) {
        final barcode = e.barcode.trim();
        if (barcode.isEmpty) continue;

        final incomingStock =
            (e.stockCode != null && e.stockCode!.trim().isNotEmpty)
                ? e.stockCode!.trim()
                : null;

        final existingRows = await txn.query(
          AppConstants.barcodeTable,
          where: 'TRIM(barcode) = ?',
          whereArgs: [barcode],
          limit: 1,
        );

        if (existingRows.isEmpty) {
          // Yeni kayit.
          await txn.insert(
            AppConstants.barcodeTable,
            {
              'barcode': barcode,
              'product_name': e.productName,
              'stock_code': incomingStock,
              'source': e.source.dbValue,
              'imported_at': e.importedAt.millisecondsSinceEpoch,
            },
          );
          continue;
        }

        final existing = BarcodeEntry.fromMap(existingRows.first);
        // forceOverwrite: gelen her zaman kazanir (kullanici elle girdi).
        final incomingWins =
            forceOverwrite || e.source.priority >= existing.source.priority;

        // Urun adi: gelen kazandiysa degisir (en dogru tanim = elle girilen).
        final newName = incomingWins ? e.productName : existing.productName;
        // Kaynak: yalnizca gelen kazandiysa guncellenir.
        final newSource = incomingWins ? e.source : existing.source;
        // Stok kodu: gelen dolu VE kazandiysa yaz; aksi halde eskiyi koru.
        final newStock = (incomingStock != null && incomingWins)
            ? incomingStock
            : existing.stockCode;

        await txn.update(
          AppConstants.barcodeTable,
          {
            'product_name': newName,
            'stock_code': newStock,
            'source': newSource.dbValue,
            'imported_at': e.importedAt.millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      }
    });
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
