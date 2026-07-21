import '../datasources/barcode_directory_datasource.dart';
import '../models/barcode_entry.dart';

/// Barkod dizini icin repository.
class BarcodeDirectoryRepository {
  final BarcodeDirectoryDataSource _local;
  BarcodeDirectoryRepository(this._local);

  Future<String?> findProductName(String barcode) =>
      _local.findProductName(barcode);
  Future<BarcodeEntry?> findEntryByBarcode(String barcode) =>
      _local.findEntryByBarcode(barcode);
  Future<BarcodeEntry?> findEntryByStockCode(String stockCode) =>
      _local.findEntryByStockCode(stockCode);
  Future<int> importAll(List<BarcodeEntry> entries,
          {bool forceOverwrite = false}) =>
      _local.importAll(entries, forceOverwrite: forceOverwrite);
  Future<List<BarcodeEntry>> getAll() => _local.getAll();
  /// Barkod dizininde bu barkod icin kayitli yerel foto yolu (reyon/etiket).
  Future<String?> getLocalImage(String barcode) =>
      _local.getLocalImage(barcode);
  /// Ad / barkod / stok kodu icinde serbest arama (palete urun ekleme).
  Future<List<BarcodeEntry>> search(String query, {int limit = 30}) =>
      _local.search(query, limit: limit);
  Future<int> count() => _local.count();
  Future<void> clearAll() => _local.clearAll();
  Future<void> deleteById(int id) => _local.deleteById(id);
  Future<int> countSimilar({
    required int excludeId,
    required String productName,
    required String barcode,
  }) =>
      _local.countSimilar(
        excludeId: excludeId,
        productName: productName,
        barcode: barcode,
      );
}
