import '../constants/app_constants.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  TESHIR (v144)
///  Reyon disinda teshirde (stand / ada / palet teshiri) duran urunler.
///  Barkod okutularak listeye eklenir. Fiyat degisimi sirasinda eslesen
///  urun bu listedeyse, TESHIR ETIKETI de gerekir mi diye sorulur ve
///  onaylanirsa barkod etiket basim kuyruguna eklenir.
/// ════════════════════════════════════════════════════════════════════
class TeshirService {
  TeshirService._();
  static final TeshirService instance = TeshirService._();

  /// Teshire ekle (ayni barkod varsa adi/notu tazeler).
  Future<void> add(String barcode, {String? productName, String? note}) async {
    final db = await DatabaseService.instance.database;
    final code = barcode.trim();
    if (code.isEmpty) return;
    final rows = await db.query(AppConstants.teshirTable,
        where: 'barcode = ?', whereArgs: [code], limit: 1);
    if (rows.isEmpty) {
      await db.insert(AppConstants.teshirTable, {
        'barcode': code,
        'product_name': productName,
        'note': note,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await db.update(
        AppConstants.teshirTable,
        {
          if (productName != null && productName.trim().isNotEmpty)
            'product_name': productName.trim(),
          if (note != null) 'note': note,
        },
        where: 'barcode = ?',
        whereArgs: [code],
      );
    }
  }

  /// Teshirdeki tum urunler — en son eklenen ustte.
  Future<List<Map<String, Object?>>> list() async {
    final db = await DatabaseService.instance.database;
    return db.query(AppConstants.teshirTable, orderBy: 'added_at DESC');
  }

  /// Bu barkod teshirde mi? (fiyat degisiminde sorulacak mi)
  Future<bool> isOnDisplay(String barcode) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.teshirTable,
        columns: ['id'],
        where: 'barcode = ?',
        whereArgs: [barcode.trim()],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// Teshir kaydini getir (ad/not gostermek icin).
  Future<Map<String, Object?>?> find(String barcode) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.teshirTable,
        where: 'barcode = ?', whereArgs: [barcode.trim()], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> remove(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.teshirTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setNote(int id, String? note) async {
    final db = await DatabaseService.instance.database;
    await db.update(AppConstants.teshirTable, {'note': note},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await DatabaseService.instance.database;
    final r = await db
        .rawQuery('SELECT COUNT(*) c FROM ${AppConstants.teshirTable}');
    return (r.first['c'] as int?) ?? 0;
  }
}
