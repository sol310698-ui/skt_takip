import '../datasources/count_datasource.dart';
import '../models/count_item.dart';

/// Bagimsiz sayim repository.
class CountRepository {
  final CountDataSource _local;
  CountRepository(this._local);

  Future<List<CountItem>> getAll() => _local.getAll();
  Future<CountItem?> findByBarcode(String barcode) =>
      _local.findByBarcode(barcode);
  Future<int> insert(CountItem item) => _local.insert(item);
  Future<void> updateQty(int id, int qty) => _local.updateQty(id, qty);
  Future<void> deleteById(int id) => _local.deleteById(id);
  Future<void> clearAll() => _local.clearAll();
}
