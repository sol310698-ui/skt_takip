import '../datasources/control_list_datasource.dart';
import '../models/control_list_item.dart';

/// Yonetici kontrol listesi repository.
class ControlListRepository {
  final ControlListDataSource _local;
  ControlListRepository(this._local);

  Future<int> insertItems(List<ControlListItem> items,
          {bool replaceAll = false}) =>
      _local.insertItems(items, replaceAll: replaceAll);
  Future<List<ControlListItem>> getAll() => _local.getAll();
  Future<int> count() => _local.count();
  Future<void> setChecked(int id, bool checked) =>
      _local.setChecked(id, checked);
  Future<void> setCount(int id, int? qty) => _local.setCount(id, qty);
  Future<void> clearAllCounts() => _local.clearAllCounts();
  Future<void> deleteById(int id) => _local.deleteById(id);
  Future<void> clearAll() => _local.clearAll();
}
