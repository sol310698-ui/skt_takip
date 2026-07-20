import 'dart:convert';

import '../constants/app_constants.dart';
import 'barcode_lookup_service.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  Depo (Warehouse) — model + servis
///  Hiyerarsi: Depo > Sutun > Raf > Palet > Urun
/// ════════════════════════════════════════════════════════════════════

class Warehouse {
  final int? id;
  final String name;
  final DateTime createdAt;
  const Warehouse({this.id, required this.name, required this.createdAt});

  factory Warehouse.fromMap(Map<String, Object?> m) => Warehouse(
        id: m['id'] as int?,
        name: m['name'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class WhShelf {
  final int? id;
  final int warehouseId;
  final int columnNo;
  final int shelfNo;
  final int capacity; // kac palet alir
  final String? label;
  const WhShelf({
    this.id,
    required this.warehouseId,
    required this.columnNo,
    required this.shelfNo,
    required this.capacity,
    this.label,
  });

  String get code => label ?? 'S$columnNo-R$shelfNo';

  factory WhShelf.fromMap(Map<String, Object?> m) => WhShelf(
        id: m['id'] as int?,
        warehouseId: m['warehouse_id'] as int,
        columnNo: m['column_no'] as int,
        shelfNo: m['shelf_no'] as int,
        capacity: (m['capacity'] as int?) ?? 1,
        label: m['label'] as String?,
      );
}

class WhPallet {
  final int? id;
  final int warehouseId;
  final int? shelfId;   // null + floorNo==null → bekleme; null + floorNo≥0 → zemin
  final int? floorNo;   // zemin pozisyonu (0-based); null = rafta veya bekleme
  final String code;
  final String? note;
  final String? imagePath;
  final DateTime createdAt;
  const WhPallet({
    this.id,
    required this.warehouseId,
    this.shelfId,
    this.floorNo,
    required this.code,
    this.note,
    this.imagePath,
    required this.createdAt,
  });

  bool get isOnFloor => floorNo != null;
  bool get isUnstacked => shelfId == null && floorNo == null;

  factory WhPallet.fromMap(Map<String, Object?> m) => WhPallet(
        id: m['id'] as int?,
        warehouseId: m['warehouse_id'] as int,
        shelfId: m['shelf_id'] as int?,
        floorNo: m['floor_no'] as int?,
        code: m['code'] as String,
        note: m['note'] as String?,
        imagePath: m['image_path'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class WhPalletItem {
  final int? id;
  final int palletId;
  final String barcode;
  final String? productName;
  final int quantity;
  final DateTime addedAt;
  const WhPalletItem({
    this.id,
    required this.palletId,
    required this.barcode,
    this.productName,
    required this.quantity,
    required this.addedAt,
  });

  factory WhPalletItem.fromMap(Map<String, Object?> m) => WhPalletItem(
        id: m['id'] as int?,
        palletId: m['pallet_id'] as int,
        barcode: m['barcode'] as String,
        productName: m['product_name'] as String?,
        quantity: (m['quantity'] as int?) ?? 1,
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'pallet_id': palletId,
        'barcode': barcode,
        'product_name': productName,
        'quantity': quantity,
        'added_at': addedAt.millisecondsSinceEpoch,
      };
}

/// Raf + uzerindeki palet sayisi (harita gosterimi).
class ShelfSummary {
  final WhShelf shelf;
  final int palletCount;
  const ShelfSummary({required this.shelf, required this.palletCount});
  bool get isFull => palletCount >= shelf.capacity;
  bool get isEmpty => palletCount == 0;
  double get fillRatio =>
      shelf.capacity == 0 ? 0 : palletCount / shelf.capacity;
}

/// Palet + icindeki kalem/adet ozeti.
class PalletSummary {
  final WhPallet pallet;
  final int itemTypes; // kac cesit urun
  final int totalQty; // toplam adet
  final WhShelf? shelf;
  const PalletSummary({
    required this.pallet,
    required this.itemTypes,
    required this.totalQty,
    this.shelf,
  });
}

/// Urun arama sonucu: hangi palet, hangi raf, ne kadar.
class ProductLocation {
  final WhPalletItem item;
  final WhPallet pallet;
  final WhShelf? shelf;
  const ProductLocation(
      {required this.item, required this.pallet, this.shelf});
}

/// ════════════════════════════════════════════════════════════════════
class WarehouseService {
  WarehouseService._();
  static final WarehouseService instance = WarehouseService._();

  // ── Depo ────────────────────────────────────────────────────────────
  Future<int> createWarehouse(String name) async {
    final db = await DatabaseService.instance.database;
    return db.insert(AppConstants.warehouseTable, {
      'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Warehouse>> getWarehouses() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.warehouseTable,
        orderBy: 'created_at DESC');
    return rows.map(Warehouse.fromMap).toList();
  }

  Future<Warehouse?> getWarehouse(int id) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.warehouseTable,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Warehouse.fromMap(rows.first);
  }

  Future<void> deleteWarehouse(int id) async {
    final db = await DatabaseService.instance.database;
    // Paletlerin urunlerini, paletleri, raflari, depoyu sil.
    final pallets = await db.query(AppConstants.whPalletTable,
        columns: ['id'], where: 'warehouse_id = ?', whereArgs: [id]);
    for (final p in pallets) {
      await db.delete(AppConstants.whPalletItemTable,
          where: 'pallet_id = ?', whereArgs: [p['id']]);
    }
    await db.delete(AppConstants.whPalletTable,
        where: 'warehouse_id = ?', whereArgs: [id]);
    await db.delete(AppConstants.whShelfTable,
        where: 'warehouse_id = ?', whereArgs: [id]);
    await db.delete(AppConstants.warehouseTable,
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Raflar ──────────────────────────────────────────────────────────
  /// Depo kurulumunda toplu raf ekleme.
  Future<void> addShelves(int warehouseId, List<WhShelf> shelves) async {
    final db = await DatabaseService.instance.database;
    final batch = db.batch();
    for (final s in shelves) {
      batch.insert(AppConstants.whShelfTable, {
        'warehouse_id': warehouseId,
        'column_no': s.columnNo,
        'shelf_no': s.shelfNo,
        'capacity': s.capacity,
        'label': s.label,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<WhShelf>> getShelves(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whShelfTable,
        where: 'warehouse_id = ?',
        whereArgs: [warehouseId],
        orderBy: 'column_no ASC, shelf_no ASC');
    return rows.map(WhShelf.fromMap).toList();
  }

  // ── Depo DUZENLEME (kurulumdan SONRA) ─────────────────────────────
  /// Bir rafin palet kapasitesini (raf basina kac palet alacagini)
  /// sonradan degistirir.
  Future<void> updateShelfCapacity(int shelfId, int capacity) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.whShelfTable,
      {'capacity': capacity.clamp(1, 999)},
      where: 'id = ?',
      whereArgs: [shelfId],
    );
  }

  /// Bir suتuna YENI bir raf ekler (mevcut en ust rafin bir ustune).
  /// Depo kurulumdan sonra "bu sutuna bir raf daha ekle" icin.
  Future<int> addShelfToColumn(
      int warehouseId, int columnNo, int capacity) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whShelfTable,
        columns: ['shelf_no'],
        where: 'warehouse_id = ? AND column_no = ?',
        whereArgs: [warehouseId, columnNo]);
    var maxShelf = 0;
    for (final r in rows) {
      final s = r['shelf_no'] as int;
      if (s > maxShelf) maxShelf = s;
    }
    return db.insert(AppConstants.whShelfTable, {
      'warehouse_id': warehouseId,
      'column_no': columnNo,
      'shelf_no': maxShelf + 1,
      'capacity': capacity.clamp(1, 999),
    });
  }

  /// Bir rafi siler. Uzerinde palet varsa GUVENLIK icin silmez (false
  /// doner) - once paletlerin tasinmasi/silinmesi gerekir.
  Future<bool> deleteShelf(int shelfId) async {
    final db = await DatabaseService.instance.database;
    final onIt = await db.query(AppConstants.whPalletTable,
        columns: ['id'], where: 'shelf_id = ?', whereArgs: [shelfId]);
    if (onIt.isNotEmpty) return false;
    await db.delete(AppConstants.whShelfTable,
        where: 'id = ?', whereArgs: [shelfId]);
    return true;
  }

  /// Harita icin: her raf + uzerindeki palet sayisi.
  Future<List<ShelfSummary>> getShelfSummaries(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final shelves = await getShelves(warehouseId);
    final result = <ShelfSummary>[];
    for (final s in shelves) {
      final c = (await db.rawQuery(
              'SELECT COUNT(*) c FROM ${AppConstants.whPalletTable} WHERE shelf_id = ?',
              [s.id]))
          .first['c'] as int;
      result.add(ShelfSummary(shelf: s, palletCount: c));
    }
    return result;
  }

  /// Depodaki sutun numaralari (harita kolonlari).
  Future<List<int>> getColumns(int warehouseId) async {
    final shelves = await getShelves(warehouseId);
    final cols = shelves.map((s) => s.columnNo).toSet().toList()..sort();
    return cols;
  }

  // ── Paletler ────────────────────────────────────────────────────────
  /// Palet olustur. shelfId verilirse direkt istifle (kapasite kontrollu).
  /// floorNo verilirse zemine al (0-based). Ikisi de null = bekleme.
  /// Donen: olusan palet id, ya da kapasite doluysa -1.
  Future<int> createPallet({
    required int warehouseId,
    int? shelfId,
    int? floorNo,
    required String code,
    String? note,
  }) async {
    final db = await DatabaseService.instance.database;
    if (shelfId != null && !await _shelfHasSpace(shelfId)) {
      return -1; // raf dolu
    }
    return db.insert(AppConstants.whPalletTable, {
      'warehouse_id': warehouseId,
      'shelf_id': shelfId,
      'floor_no': floorNo,
      'code': code.trim(),
      'note': note,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> _shelfHasSpace(int shelfId) async {
    final db = await DatabaseService.instance.database;
    final shelf = (await db.query(AppConstants.whShelfTable,
            where: 'id = ?', whereArgs: [shelfId], limit: 1))
        .first;
    final cap = (shelf['capacity'] as int?) ?? 1;
    final count = (await db.rawQuery(
            'SELECT COUNT(*) c FROM ${AppConstants.whPalletTable} WHERE shelf_id = ?',
            [shelfId]))
        .first['c'] as int;
    return count < cap;
  }

  /// Bir rafin paletleri.
  Future<List<PalletSummary>> getPalletsOnShelf(int shelfId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletTable,
        where: 'shelf_id = ?', whereArgs: [shelfId], orderBy: 'code ASC');
    return _summarize(rows);
  }

  /// Istiflenmemis (bekleyen) paletler.
  /// Zemin paletleri.
  Future<List<PalletSummary>> getFloorPallets(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletTable,
        where: 'warehouse_id = ? AND floor_no IS NOT NULL',
        whereArgs: [warehouseId],
        orderBy: 'floor_no ASC, created_at DESC');
    return _summarize(rows);
  }

  Future<List<PalletSummary>> getUnstackedPallets(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletTable,
        where: 'warehouse_id = ? AND shelf_id IS NULL AND floor_no IS NULL',
        whereArgs: [warehouseId],
        orderBy: 'created_at DESC');
    return _summarize(rows);
  }

  Future<List<PalletSummary>> getAllPallets(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletTable,
        where: 'warehouse_id = ?',
        whereArgs: [warehouseId],
        orderBy: 'created_at DESC');
    return _summarize(rows);
  }

  Future<List<PalletSummary>> _summarize(
      List<Map<String, Object?>> rows) async {
    final db = await DatabaseService.instance.database;
    final result = <PalletSummary>[];
    for (final r in rows) {
      final p = WhPallet.fromMap(r);
      final agg = (await db.rawQuery(
          'SELECT COUNT(*) types, COALESCE(SUM(quantity),0) total '
          'FROM ${AppConstants.whPalletItemTable} WHERE pallet_id = ?',
          [p.id]))
          .first;
      WhShelf? shelf;
      if (p.shelfId != null) {
        final sr = await db.query(AppConstants.whShelfTable,
            where: 'id = ?', whereArgs: [p.shelfId], limit: 1);
        if (sr.isNotEmpty) shelf = WhShelf.fromMap(sr.first);
      }
      result.add(PalletSummary(
        pallet: p,
        itemTypes: (agg['types'] as int?) ?? 0,
        totalQty: ((agg['total'] as num?) ?? 0).toInt(),
        shelf: shelf,
      ));
    }
    return result;
  }

  Future<WhPallet?> getPallet(int id) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletTable,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return WhPallet.fromMap(rows.first);
  }

  /// Palet resmini günceller (kaldırmak için null geç).
  Future<void> updatePalletImage(int palletId, String? imagePath) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.whPalletTable,
      {'image_path': imagePath},
      where: 'id = ?',
      whereArgs: [palletId],
    );
  }

  /// Paleti tasi: hedef raf, zemin (floorNo) veya bekleme (ikisi de null).
  /// targetWarehouseId verilirse farkli depoya tasi.
  /// Donen: false = hedef raf dolu.
  Future<bool> movePallet(int palletId, int? targetShelfId,
      {int? floorNo, int? targetWarehouseId}) async {
    final db = await DatabaseService.instance.database;
    if (targetShelfId != null && !await _shelfHasSpace(targetShelfId)) {
      return false;
    }
    final update = <String, Object?>{
      'shelf_id': targetShelfId,
      'floor_no': floorNo,
    };
    if (targetWarehouseId != null) {
      update['warehouse_id'] = targetWarehouseId;
    }
    await db.update(AppConstants.whPalletTable, update,
        where: 'id = ?', whereArgs: [palletId]);
    return true;
  }

  /// Reyona acilan kaydi (shelf_out).
  Future<int> recordShelfOut({
    required int palletId,
    required String palletCode,
    required int warehouseId,
    required List<WhPalletItem> items,
    int? fromShelfId,
    String? fromShelfLabel,
    String? warehouseName,
    String? note,
  }) async {
    final t = WhTransfer(
      palletId: palletId,
      palletCode: palletCode,
      transferType: 'shelf_out',
      fromWarehouseId: warehouseId,
      fromShelfId: fromShelfId,
      fromWarehouseName: warehouseName,
      fromShelfLabel: fromShelfLabel,
      note: note,
      createdAt: DateTime.now(),
      itemsSnapshot: items,
    );
    return recordTransfer(t);
  }

  Future<void> deletePallet(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.whPalletItemTable,
        where: 'pallet_id = ?', whereArgs: [id]);
    await db.delete(AppConstants.whPalletTable,
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Palet ici urunler ───────────────────────────────────────────────
  /// Palete urun ekle. Ayni barkod varsa adedi artirir.
  Future<void> addItemToPallet({
    required int palletId,
    required String barcode,
    int quantity = 1,
    String? productName,
  }) async {
    final db = await DatabaseService.instance.database;
    // Ad yoksa dizinden/OFF'tan bulmaya calis.
    String? name = productName;
    if (name == null || name.isEmpty) {
      name = await _resolveName(barcode);
    }
    final existing = await db.query(AppConstants.whPalletItemTable,
        where: 'pallet_id = ? AND barcode = ?',
        whereArgs: [palletId, barcode.trim()],
        limit: 1);
    if (existing.isNotEmpty) {
      final cur = WhPalletItem.fromMap(existing.first);
      await db.update(
          AppConstants.whPalletItemTable,
          {'quantity': cur.quantity + quantity},
          where: 'id = ?',
          whereArgs: [cur.id]);
    } else {
      await db.insert(AppConstants.whPalletItemTable, {
        'pallet_id': palletId,
        'barcode': barcode.trim(),
        'product_name': name,
        'quantity': quantity,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<String?> resolveName(String barcode) => _resolveName(barcode);

  Future<String?> _resolveName(String barcode) async {
    final db = await DatabaseService.instance.database;
    // Once barkod dizini.
    final dir = await db.query(AppConstants.barcodeTable,
        where: 'barcode = ?', whereArgs: [barcode.trim()], limit: 1);
    if (dir.isNotEmpty) {
      return dir.first['product_name'] as String?;
    }
    // Sonra urunler tablosu.
    final prod = await db.query(AppConstants.productTable,
        where: 'barcode = ?', whereArgs: [barcode.trim()], limit: 1);
    if (prod.isNotEmpty) {
      return prod.first['name'] as String?;
    }
    // Son care: OFF (internet).
    try {
      final off =
          await BarcodeLookupService.instance.lookupDetailed(barcode);
      if (off.found) return off.name;
    } catch (_) {}
    return null;
  }

  Future<List<WhPalletItem>> getPalletItems(int palletId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletItemTable,
        where: 'pallet_id = ?',
        whereArgs: [palletId],
        orderBy: 'added_at DESC');
    return rows.map(WhPalletItem.fromMap).toList();
  }

  /// Paletten urun cikar (adet azalt; 0'a inerse sil).
  Future<void> removeItemQuantity(int itemId, int amount) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whPalletItemTable,
        where: 'id = ?', whereArgs: [itemId], limit: 1);
    if (rows.isEmpty) return;
    final item = WhPalletItem.fromMap(rows.first);
    final newQty = item.quantity - amount;
    if (newQty <= 0) {
      await db.delete(AppConstants.whPalletItemTable,
          where: 'id = ?', whereArgs: [itemId]);
    } else {
      await db.update(AppConstants.whPalletItemTable, {'quantity': newQty},
          where: 'id = ?', whereArgs: [itemId]);
    }
  }

  // ── Arama ───────────────────────────────────────────────────────────
  /// Barkodu tum depoda ara: hangi palet(ler)de, hangi raf(lar)da.
  Future<List<ProductLocation>> findProduct(
      int warehouseId, String barcode) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery('''
      SELECT pi.* FROM ${AppConstants.whPalletItemTable} pi
      JOIN ${AppConstants.whPalletTable} p ON p.id = pi.pallet_id
      WHERE p.warehouse_id = ? AND pi.barcode = ?
    ''', [warehouseId, barcode.trim()]);

    final result = <ProductLocation>[];
    for (final r in rows) {
      final item = WhPalletItem.fromMap(r);
      final pallet = await getPallet(item.palletId);
      if (pallet == null) continue;
      WhShelf? shelf;
      if (pallet.shelfId != null) {
        final sr = await db.query(AppConstants.whShelfTable,
            where: 'id = ?', whereArgs: [pallet.shelfId], limit: 1);
        if (sr.isNotEmpty) shelf = WhShelf.fromMap(sr.first);
      }
      result.add(
          ProductLocation(item: item, pallet: pallet, shelf: shelf));
    }
    return result;
  }

  /// "Zemin" adli ozel paleti bulur, yoksa olusturur (floorNo=0).
  /// Yere alinan urunler bu palette toplanir.
  Future<int> getOrCreateFloorPallet(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final existing = await db.query(AppConstants.whPalletTable,
        where: "warehouse_id = ? AND code = 'Zemin' AND floor_no IS NOT NULL",
        whereArgs: [warehouseId],
        limit: 1);
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return createPallet(
      warehouseId: warehouseId,
      floorNo: 0,
      code: 'Zemin',
    );
  }

  /// Bir kalemin tamamini veya bir kismini baska palete tasir.
  /// Kaynak paletten [amount] adet cikar, hedef palete ekler.
  Future<void> transferItemToPallet({
    required int sourceItemId,
    required int targetPalletId,
    required int amount,
  }) async {
    final db = await DatabaseService.instance.database;
    // Kaynak kalemi bul
    final rows = await db.query(AppConstants.whPalletItemTable,
        where: 'id = ?', whereArgs: [sourceItemId], limit: 1);
    if (rows.isEmpty) return;
    final item = WhPalletItem.fromMap(rows.first);
    // Hedef palete ekle (varsa adedi artir)
    await addItemToPallet(
      palletId: targetPalletId,
      barcode: item.barcode,
      quantity: amount,
      productName: item.productName,
    );
    // Kaynaktan cikar
    await removeItemQuantity(sourceItemId, amount);
  }

  Future<int> recordTransfer(WhTransfer t) async {
    final db = await DatabaseService.instance.database;
    return db.insert(AppConstants.whTransferTable, t.toMap()..remove('id'));
  }

  Future<List<WhTransfer>> getTransfers(int palletId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whTransferTable,
        where: 'pallet_id = ?',
        whereArgs: [palletId],
        orderBy: 'created_at DESC');
    return rows.map(WhTransfer.fromMap).toList();
  }

  Future<List<WhTransfer>> getAllTransfers(int warehouseId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.whTransferTable,
        where: 'from_warehouse_id = ? OR to_warehouse_id = ?',
        whereArgs: [warehouseId, warehouseId],
        orderBy: 'created_at DESC');
    return rows.map(WhTransfer.fromMap).toList();
  }
}

/// Transfer kaydi modeli.
class WhTransfer {
  final int? id;
  final int palletId;
  final String palletCode;
  final String transferType; // 'internal' | 'external'
  final int? fromWarehouseId;
  final int? fromShelfId;
  final String? fromWarehouseName;
  final String? fromShelfLabel;
  final int? toWarehouseId;
  final int? toShelfId;
  final String? toWarehouseName;
  final String? toShelfLabel;
  final String? toExternalName;
  final String? toExternalAddress;
  final String? note;
  final DateTime createdAt;
  final List<WhPalletItem> itemsSnapshot;

  const WhTransfer({
    this.id,
    required this.palletId,
    required this.palletCode,
    this.transferType = 'internal',
    this.fromWarehouseId,
    this.fromShelfId,
    this.fromWarehouseName,
    this.fromShelfLabel,
    this.toWarehouseId,
    this.toShelfId,
    this.toWarehouseName,
    this.toShelfLabel,
    this.toExternalName,
    this.toExternalAddress,
    this.note,
    required this.createdAt,
    this.itemsSnapshot = const [],
  });

  factory WhTransfer.fromMap(Map<String, Object?> m) {
    List<WhPalletItem> items = [];
    try {
      final raw = m['items_snapshot'] as String? ?? '[]';
      final list = jsonDecode(raw) as List;
      items = list
          .map((e) => WhPalletItem.fromMap(Map<String, Object?>.from(e as Map)))
          .toList();
    } catch (_) {}
    return WhTransfer(
      id: m['id'] as int?,
      palletId: m['pallet_id'] as int,
      palletCode: m['pallet_code'] as String,
      transferType: (m['transfer_type'] as String?) ?? 'internal',
      fromWarehouseId: m['from_warehouse_id'] as int?,
      fromShelfId: m['from_shelf_id'] as int?,
      fromWarehouseName: m['from_warehouse_name'] as String?,
      fromShelfLabel: m['from_shelf_label'] as String?,
      toWarehouseId: m['to_warehouse_id'] as int?,
      toShelfId: m['to_shelf_id'] as int?,
      toWarehouseName: m['to_warehouse_name'] as String?,
      toShelfLabel: m['to_shelf_label'] as String?,
      toExternalName: m['to_external_name'] as String?,
      toExternalAddress: m['to_external_address'] as String?,
      note: m['note'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      itemsSnapshot: items,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'pallet_id': palletId,
        'pallet_code': palletCode,
        'transfer_type': transferType,
        'from_warehouse_id': fromWarehouseId,
        'from_shelf_id': fromShelfId,
        'from_warehouse_name': fromWarehouseName,
        'from_shelf_label': fromShelfLabel,
        'to_warehouse_id': toWarehouseId,
        'to_shelf_id': toShelfId,
        'to_warehouse_name': toWarehouseName,
        'to_shelf_label': toShelfLabel,
        'to_external_name': toExternalName,
        'to_external_address': toExternalAddress,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'items_snapshot': jsonEncode(
            itemsSnapshot.map((i) => i.toMap()).toList()),
      };
}
