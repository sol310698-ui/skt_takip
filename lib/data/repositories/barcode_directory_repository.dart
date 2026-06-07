import '../datasources/barcode_directory_datasource.dart';
import '../models/barcode_entry.dart';

/// Barkod dizini icin repository.
class BarcodeDirectoryRepository {
  final BarcodeDirectoryDataSource _local;
  BarcodeDirectoryRepository(this._local);

  Future<String?> findProductName(String barcode) =>
      _local.findProductName(barcode);
  Future<int> importAll(List<BarcodeEntry> entries) =>
      _local.importAll(entries);
  Future<List<BarcodeEntry>> getAll() => _local.getAll();
  Future<int> count() => _local.count();
  Future<void> clearAll() => _local.clearAll();
}
