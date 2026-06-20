import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/label_item.dart';
import 'database_service.dart';

/// Etiket Basim ekranindaki 5 sekmenin (Kalin Reyon, Ince Reyon, A4,
/// A4 Ikili, A4 Uclu) aktif urun listelerini KALICI olarak saklar.
/// Ekrandan cikip geri girince veya uygulama kapanip acilinca listeler
/// kaybolmaz. Sadece "Akışı Başlat" ile sonuna gidip "Bitir"e basinca
/// o sekmenin listesi bilerek temizlenir (clearGroup).
class LabelActiveListsService {
  LabelActiveListsService._();
  static final LabelActiveListsService instance = LabelActiveListsService._();

  /// Tum gruplarin kayitli listelerini okur. Hic kayit yoksa bos liste doner.
  Future<Map<String, List<LabelItem>>> loadAll() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.labelActiveListsTable);
    final result = <String, List<LabelItem>>{};
    for (final row in rows) {
      final groupKey = row['group_key'] as String;
      final jsonStr = row['items_json'] as String;
      try {
        final list = (jsonDecode(jsonStr) as List)
            .map((e) => LabelItem.fromJson(e as Map<String, Object?>))
            .toList();
        result[groupKey] = list;
      } catch (_) {
        result[groupKey] = [];
      }
    }
    return result;
  }

  /// Bir grubun listesini kaydeder (mevcutsa uzerine yazar).
  Future<void> saveGroup(String groupKey, List<LabelItem> items) async {
    final db = await DatabaseService.instance.database;
    if (items.isEmpty) {
      await db.delete(
        AppConstants.labelActiveListsTable,
        where: 'group_key = ?',
        whereArgs: [groupKey],
      );
      return;
    }
    final jsonStr = jsonEncode(items.map((e) => e.toJson()).toList());
    await db.insert(
      AppConstants.labelActiveListsTable,
      {'group_key': groupKey, 'items_json': jsonStr},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Bir grubun kayitli listesini siler (Akis "Bitir" sonrasi).
  Future<void> clearGroup(String groupKey) async {
    final db = await DatabaseService.instance.database;
    await db.delete(
      AppConstants.labelActiveListsTable,
      where: 'group_key = ?',
      whereArgs: [groupKey],
    );
  }
}
