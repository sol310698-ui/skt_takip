import '../constants/app_constants.dart';
import 'database_service.dart';
import 'warehouse_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYONA ACILACAKLAR (v141)
///  Barkod okutarak olusturulan is listesi: reyona tasinacak urunler.
///  Her ogenin depodaki palet konumlari bulunur; "Depodan Cikar" akisi
///  FEFO parti dusumu + palet kalemi dusumuyle stoklari gunceller ve
///  ogeyi TAMAM olarak isaretler.
/// ════════════════════════════════════════════════════════════════════
class ShelfRestockService {
  ShelfRestockService._();
  static final ShelfRestockService instance = ShelfRestockService._();

  /// Listeye ekle; ayni barkoddan BEKLEYEN kayit varsa adedini artirir.
  /// Donen deger: kayit id.
  Future<int> add(String barcode, {String? productName, int qty = 1}) async {
    final db = await DatabaseService.instance.database;
    final existing = await db.query(AppConstants.restockTable,
        where: 'barcode = ? AND done = 0',
        whereArgs: [barcode.trim()],
        limit: 1);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      final cur = (existing.first['quantity'] as int?) ?? 1;
      await db.update(AppConstants.restockTable, {'quantity': cur + qty},
          where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert(AppConstants.restockTable, {
      'barcode': barcode.trim(),
      'product_name': productName,
      'quantity': qty,
      'added_at': DateTime.now().millisecondsSinceEpoch,
      'done': 0,
    });
  }

  /// Tum liste: bekleyenler once (yeni eklenen ustte), tamamlar sonda.
  Future<List<Map<String, Object?>>> list() async {
    final db = await DatabaseService.instance.database;
    return db.query(AppConstants.restockTable,
        orderBy: 'done ASC, added_at DESC');
  }

  Future<void> updateQty(int id, int qty) async {
    final db = await DatabaseService.instance.database;
    await db.update(AppConstants.restockTable, {'quantity': qty},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Sirket uygulamasindan gelen urun adini kaydet (isim bilinmiyordu).
  Future<void> updateName(int id, String name) async {
    final db = await DatabaseService.instance.database;
    await db.update(AppConstants.restockTable, {'product_name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Adi henuz bilinmeyen (barkodla ayni olan ya da bos) BEKLEYEN kayit.
  /// Sirket uygulamasindan veri gelince hangi ogeye yazilacagini bulmak
  /// icin kullanilir.
  Future<Map<String, Object?>?> pendingByBarcode(String barcode) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.restockTable,
        where: 'barcode = ? AND done = 0',
        whereArgs: [barcode.trim()],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> remove(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.restockTable,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearDone() async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.restockTable, where: 'done = 1');
  }

  /// DEPODAN CIKAR: verilen palet kaleminden [qty] adet duser
  /// (FEFO parti dusumu dahil) ve restock ogesini TAMAM isaretler.
  Future<void> pullFromWarehouse({
    required int restockId,
    required int palletItemId,
    required int qty,
  }) async {
    await WarehouseService.instance
        .consumeLinkedBatches(palletItemId, qty);
    await WarehouseService.instance.removeItemQuantity(palletItemId, qty);
    final db = await DatabaseService.instance.database;
    await db.update(
        AppConstants.restockTable,
        {'done': 1, 'done_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [restockId]);
  }

  /// Depoda bulunamadi ama yine de tamamlandi isaretlemek icin
  /// (or. zeminden/koliden acildi).
  Future<void> markDone(int id) async {
    final db = await DatabaseService.instance.database;
    await db.update(
        AppConstants.restockTable,
        {'done': 1, 'done_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id]);
  }
}
