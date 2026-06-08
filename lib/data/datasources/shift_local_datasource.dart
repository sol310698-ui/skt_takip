import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/shift_entry.dart';

/// Mesai kayitlari icin yerel veri kaynagi.
class ShiftLocalDataSource {
  final DatabaseService _dbService;
  ShiftLocalDataSource(this._dbService);

  Future<List<ShiftEntry>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.shiftTable,
      orderBy: 'clock_in DESC',
    );
    return rows.map(ShiftEntry.fromMap).toList();
  }

  /// Acik (cikis yapilmamis) vardiya varsa dondur.
  Future<ShiftEntry?> getOpenShift() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.shiftTable,
      where: 'clock_out IS NULL',
      orderBy: 'clock_in DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ShiftEntry.fromMap(rows.first);
  }

  Future<int> insert(ShiftEntry s) async {
    final db = await _dbService.database;
    return db.insert(AppConstants.shiftTable, s.toMap());
  }

  Future<int> update(ShiftEntry s) async {
    final db = await _dbService.database;
    return db.update(
      AppConstants.shiftTable,
      s.toMap(),
      where: 'id = ?',
      whereArgs: [s.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _dbService.database;
    return db.delete(
      AppConstants.shiftTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
