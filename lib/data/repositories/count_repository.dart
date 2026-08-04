import '../datasources/count_datasource.dart';
import '../models/count_item.dart';

/// Sayim repository: oturumlar + oturuma bagli kalemler.
class CountRepository {
  final CountDataSource _local;
  CountRepository(this._local);

  // Oturumlar
  Future<List<CountSession>> getSessions() => _local.getSessions();
  Future<CountSession?> getSession(int id) => _local.getSession(id);
  Future<int> createSession(String name, {String? note}) =>
      _local.createSession(name, note: note);
  Future<void> renameSession(int id, String name) =>
      _local.renameSession(id, name);
  Future<void> setClosed(int id, bool closed) => _local.setClosed(id, closed);
  Future<void> deleteSession(int id) => _local.deleteSession(id);

  // Kalemler
  Future<List<CountItem>> getItems(int sessionId) => _local.getItems(sessionId);
  Future<CountItem?> findByBarcode(int sessionId, String barcode) =>
      _local.findByBarcode(sessionId, barcode);
  Future<int> insert(CountItem item) => _local.insert(item);
  Future<void> updateQty(int id, int qty) => _local.updateQty(id, qty);
  Future<void> deleteById(int id) => _local.deleteById(id);
  Future<void> clearSession(int sessionId) => _local.clearSession(sessionId);
}
