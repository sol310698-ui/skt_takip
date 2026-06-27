import '../../core/constants/app_constants.dart';
import '../../core/services/database_service.dart';
import '../models/control_list_item.dart';

/// Yonetici kontrol listesi yerel veri kaynagi.
class ControlListDataSource {
  final DatabaseService _dbService;
  ControlListDataSource(this._dbService);

  /// Yeni bir liste yukle.
  ///
  /// replaceAll=true ise once mevcut liste TAMAMEN silinir (eski davranis;
  /// artik UI'dan cagrilmiyor cunku veri kaybina yol aciyordu).
  ///
  /// replaceAll=false (VARSAYILAN, MERGE): mevcut liste KORUNUR. Gelen her
  /// urun barkoduna (barkod yoksa stok koduna) gore eslenip:
  ///   - Mevcutsa: bilgileri guncellenir AMA kullanicinin 'checked'
  ///     (kontrol edildi) durumu KORUNUR — yeni foto/Excel yuklemek
  ///     kullanicinin yaptigi kontrolleri silmemeli.
  ///   - Yoksa: yeni satir olarak eklenir.
  /// Boylece arka arkaya foto/Excel yuklemek eski urunleri SILMEZ; ekler
  /// veya gunceller. "Yeni foto eskisini sildi" hatasinin koku buydu.
  Future<int> insertItems(List<ControlListItem> items,
      {bool replaceAll = false}) async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete(AppConstants.controlListTable);
        for (final item in items) {
          final map = item.toMap()..remove('id');
          await txn.insert(AppConstants.controlListTable, map);
        }
        return;
      }

      // ── MERGE ──
      for (final item in items) {
        final bc = item.barcode?.trim();
        final sc = item.stockCode?.trim();

        // Eslestirme anahtari: once barkod, yoksa stok kodu.
        List<Map<String, Object?>> existing = const [];
        if (bc != null && bc.isNotEmpty) {
          existing = await txn.query(
            AppConstants.controlListTable,
            where: 'TRIM(barcode) = ?',
            whereArgs: [bc],
            limit: 1,
          );
        } else if (sc != null && sc.isNotEmpty) {
          existing = await txn.query(
            AppConstants.controlListTable,
            where: 'TRIM(stock_code) = ?',
            whereArgs: [sc],
            limit: 1,
          );
        }

        final map = item.toMap()..remove('id');

        if (existing.isNotEmpty) {
          // Mevcut satiri guncelle; kullanicinin 'checked' durumunu KORU.
          final existingChecked =
              (existing.first['checked'] as int? ?? 0) == 1;
          map['checked'] = existingChecked ? 1 : 0;
          await txn.update(
            AppConstants.controlListTable,
            map,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        } else {
          await txn.insert(AppConstants.controlListTable, map);
        }
      }
    });
    return items.length;
  }

  Future<List<ControlListItem>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query(
      AppConstants.controlListTable,
      orderBy: 'id ASC',
    );
    return rows.map(ControlListItem.fromMap).toList();
  }

  Future<int> count() async {
    final db = await _dbService.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) as c FROM ${AppConstants.controlListTable}');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> setChecked(int id, bool checked) async {
    final db = await _dbService.database;
    await db.update(
      AppConstants.controlListTable,
      {'checked': checked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteById(int id) async {
    final db = await _dbService.database;
    await db.delete(
      AppConstants.controlListTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await _dbService.database;
    await db.delete(AppConstants.controlListTable);
  }
}
