import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../../data/models/checklist.dart';

/// Kontrol listeleri (oturumlu) icin CRUD servisi.
class ChecklistService {
  ChecklistService._();
  static final ChecklistService instance = ChecklistService._();

  // ── Listeler (oturumlar) ──

  /// Tum listeleri getir (en yeni guncellenen ustte) + madde sayilari.
  Future<List<ChecklistWithCount>> getAllWithCounts() async {
    final db = await DatabaseService.instance.database;
    final lists = await db.query(
      AppConstants.checklistTable,
      orderBy: 'updated_at DESC',
    );
    final result = <ChecklistWithCount>[];
    for (final row in lists) {
      final cl = Checklist.fromMap(row);
      final total = await db.rawQuery(
        'SELECT COUNT(*) c FROM ${AppConstants.checklistItemTable} WHERE checklist_id = ?',
        [cl.id],
      );
      final done = await db.rawQuery(
        'SELECT COUNT(*) c FROM ${AppConstants.checklistItemTable} WHERE checklist_id = ? AND done = 1',
        [cl.id],
      );
      result.add(ChecklistWithCount(
        checklist: cl,
        total: (total.first['c'] as int?) ?? 0,
        done: (done.first['c'] as int?) ?? 0,
      ));
    }
    return result;
  }

  /// Yeni liste olustur, id dondur.
  Future<int> createList(String title, {int? color}) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now();
    return db.insert(AppConstants.checklistTable, {
      'title': title,
      'color': color,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
  }

  Future<void> renameList(int id, String title) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.checklistTable,
      {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteList(int id) async {
    final db = await DatabaseService.instance.database;
    // Maddeleri de sil (FK ON DELETE CASCADE her cihazda aktif olmayabilir).
    await db.delete(AppConstants.checklistItemTable,
        where: 'checklist_id = ?', whereArgs: [id]);
    await db.delete(AppConstants.checklistTable,
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Maddeler ──

  Future<List<ChecklistItem>> getItems(int checklistId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.checklistItemTable,
      where: 'checklist_id = ?',
      whereArgs: [checklistId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map((e) => ChecklistItem.fromMap(e)).toList();
  }

  Future<int> addItem(int checklistId, String text) async {
    final db = await DatabaseService.instance.database;
    // Sona ekle (en buyuk position + 1).
    final maxPos = await db.rawQuery(
      'SELECT MAX(position) m FROM ${AppConstants.checklistItemTable} WHERE checklist_id = ?',
      [checklistId],
    );
    final next = ((maxPos.first['m'] as int?) ?? -1) + 1;
    await _touch(checklistId);
    return db.insert(AppConstants.checklistItemTable, {
      'checklist_id': checklistId,
      'text': text,
      'done': 0,
      'position': next,
    });
  }

  Future<void> toggleItem(int itemId, bool done) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.checklistItemTable,
      {'done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> updateItemText(int itemId, String text) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.checklistItemTable,
      {'text': text},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> deleteItem(int itemId) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.checklistItemTable,
        where: 'id = ?', whereArgs: [itemId]);
  }

  /// Bir listenin tum maddelerinin isaretini kaldir (yeni gun icin sifirla).
  Future<void> resetItems(int checklistId) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.checklistItemTable,
      {'done': 0},
      where: 'checklist_id = ?',
      whereArgs: [checklistId],
    );
    await _touch(checklistId);
  }

  Future<void> _touch(int checklistId) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.checklistTable,
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [checklistId],
    );
  }
}

/// Liste + madde sayilari (liste ekraninda ilerleme gostermek icin).
class ChecklistWithCount {
  final Checklist checklist;
  final int total;
  final int done;
  const ChecklistWithCount({
    required this.checklist,
    required this.total,
    required this.done,
  });

  double get progress => total == 0 ? 0 : done / total;
}
