import '../datasources/shift_local_datasource.dart';
import '../models/shift_entry.dart';

/// Mesai kayitlari repository.
class ShiftRepository {
  final ShiftLocalDataSource _local;
  ShiftRepository(this._local);

  Future<List<ShiftEntry>> getShifts() => _local.getAll();
  Future<ShiftEntry?> getOpenShift() => _local.getOpenShift();
  Future<int> addShift(ShiftEntry s) => _local.insert(s);
  Future<int> updateShift(ShiftEntry s) => _local.update(s);
  Future<int> deleteShift(int id) => _local.delete(id);
}
