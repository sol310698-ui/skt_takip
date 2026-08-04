import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/count_item.dart';

/// Sayim verisi: OTURUMLAR (count_sessions) + kalemler (count_items).
class CountDataSource {
  final DatabaseService _dbService;
  CountDataSource(this._dbService);

  // ── OTURUMLAR ──────────────────────────────────────────────────────

  /// Tum oturumlar (en yeni ustte) + her birinin kalem/adet ozeti.
  Future<List<CountSession>> getSessions() async {
    final db = await _dbService.database;
    final sessions = await db.query(
      AppConstants.countSessionTable,
      orderBy: 'created_at DESC',
    );
    // Ozetleri tek sorguda topla.
    final sums = await db.rawQuery(
      'SELECT session_id, COUNT(*) AS kalem, COALESCE(SUM(qty),0) AS adet '
      'FROM ${AppConstants.countTable} GROUP BY session_id',
    );
    final byId = <int, Map<String, int>>{};
    for (final r in sums) {
      final sid = (r['session_id'] as int?) ?? 0;
      byId[sid] = {
        'kalem': (r['kalem'] as int?) ?? 0,
        'adet': (r['adet'] as int?) ?? 0,
      };
    }
    return sessions.map((s) {
      final sid = s['id'] as int?;
      final agg = byId[sid] ?? const {'kalem': 0, 'adet': 0};
      return CountSession.fromMap(s,
          itemCount: agg['kalem'] ?? 0, totalQty: agg['adet'] ?? 0);
    }).toList();
  }

  Future<CountSession?> getSession(int id) async {
    final db = await _dbService.database;
    final rows = await db.query(AppConstants.countSessionTable,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final agg = await db.rawQuery(
      'SELECT COUNT(*) AS kalem, COALESCE(SUM(qty),0) AS adet '
      'FROM ${AppConstants.countTable} WHERE session_id = ?',
      [id],
    );
    final kalem = (agg.first['kalem'] as int?) ?? 0;
    final adet = (agg.first['adet'] as int?) ?? 0;
    return CountSession.fromMap(rows.first, itemCount: kalem, totalQty: adet);
  }

  Future<int> createSession(String name, {String? note}) async {
    final db = await _dbService.database;
    return db.insert(AppConstants.countSessionTable, {
      'name': name,
      'note': note,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'closed_at': null,
    });
  }

  Future<void> renameSession(int id, String name) async {
    final db = await _dbService.database;
    await db.update(AppConstants.countSessionTable, {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Oturumu kapat (bitir) veya yeniden ac.
  Future<void> setClosed(int id, bool closed) async {
    final db = await _dbService.database;
    await db.update(
      AppConstants.countSessionTable,
      {'closed_at': closed ? DateTime.now().millisecondsSinceEpoch : null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Oturumu VE tum kalemlerini sil.
  Future<void> deleteSession(int id) async {
    final db = await _dbService.database;
    await db.delete(AppConstants.countTable,
        where: 'session_id = ?', whereArgs: [id]);
    await db.delete(AppConstants.countSessionTable,
        where: 'id = ?', whereArgs: [id]);
  }

  // ── KALEMLER (oturuma bagli) ───────────────────────────────────────

  Future<List<CountItem>> getItems(int sessionId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.countTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'counted_at DESC',
    );
    return rows.map((r) => CountItem.fromMap(r)).toList();
  }

  /// Bu oturumda bu barkod daha once sayildi mi?
  Future<CountItem?> findByBarcode(int sessionId, String barcode) async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.countTable,
      where: 'session_id = ? AND barcode = ?',
      whereArgs: [sessionId, barcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CountItem.fromMap(rows.first);
  }

  Future<int> insert(CountItem item) async {
    final db = await _dbService.database;
    final map = item.toMap()..remove('id');
    return db.insert(AppConstants.countTable, map);
  }

  Future<void> updateQty(int id, int qty) async {
    final db = await _dbService.database;
    await db.update(
      AppConstants.countTable,
      {'qty': qty, 'counted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteById(int id) async {
    final db = await _dbService.database;
    await db.delete(AppConstants.countTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearSession(int sessionId) async {
    final db = await _dbService.database;
    await db.delete(AppConstants.countTable,
        where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
