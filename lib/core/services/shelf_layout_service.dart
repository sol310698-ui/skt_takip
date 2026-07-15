import '../constants/app_constants.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYON DIZILIM (PLANOGRAM) — model + servis
/// ────────────────────────────────────────────────────────────────────
///  Amac: Bir reyonu (bolum x satir izgarasi) olusturmak, urunleri okuturken
///  fotograflarini cekip yerine (bolum, satir) sirayla dizmek ve daha sonra
///  kus bakisi bir dizilim (planogram) olarak gormek.
///
///  Hiyerarsi:  Reyon (ShelfUnit)  →  Hucre (bolum_no, satir_no)  →  Urun (Slot)
///
///  Cekilen her foto AYNI ZAMANDA barkod dizinine (barcode_directory) yerel
///  foto olarak yazilir; boylece internet fotografi olmayan urunlerde
///  uygulamanin her yerinde bu foto fallback olarak gosterilebilir.
/// ════════════════════════════════════════════════════════════════════

class ShelfUnit {
  final int? id;
  final int? warehouseId; // bagli oldugu depo (opsiyonel)
  final String name; // "Reyon 1", "Bakliyat" ...
  final int sections; // bolum (sutun) sayisi — soldan saga
  final int rows; // satir (kat) sayisi — ustten alta
  final DateTime createdAt;

  const ShelfUnit({
    this.id,
    this.warehouseId,
    required this.name,
    required this.sections,
    required this.rows,
    required this.createdAt,
  });

  factory ShelfUnit.fromMap(Map<String, Object?> m) => ShelfUnit(
        id: m['id'] as int?,
        warehouseId: m['warehouse_id'] as int?,
        name: m['name'] as String,
        sections: (m['sections'] as int?) ?? 1,
        rows: (m['rows'] as int?) ?? 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class ShelfSlot {
  final int? id;
  final int unitId;
  final int sectionNo; // 1-based bolum
  final int rowNo; // 1-based satir
  final int seq; // ayni hucrede soldan saga sira
  final String barcode;
  final String? productName;
  final String? photoPath; // YEREL kucuk foto
  final DateTime createdAt;

  const ShelfSlot({
    this.id,
    required this.unitId,
    required this.sectionNo,
    required this.rowNo,
    required this.seq,
    required this.barcode,
    this.productName,
    this.photoPath,
    required this.createdAt,
  });

  factory ShelfSlot.fromMap(Map<String, Object?> m) => ShelfSlot(
        id: m['id'] as int?,
        unitId: m['unit_id'] as int,
        sectionNo: m['section_no'] as int,
        rowNo: m['row_no'] as int,
        seq: (m['seq'] as int?) ?? 0,
        barcode: m['barcode'] as String,
        productName: m['product_name'] as String?,
        photoPath: m['photo_path'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// Reyon + icindeki urun sayisi (liste/kus bakisi ozeti).
class ShelfUnitSummary {
  final ShelfUnit unit;
  final int itemCount;
  final String? coverPhoto; // ilk urunun fotografi (kartta kucuk onizleme)
  const ShelfUnitSummary({
    required this.unit,
    required this.itemCount,
    this.coverPhoto,
  });
}

class ShelfLayoutService {
  ShelfLayoutService._();
  static final ShelfLayoutService instance = ShelfLayoutService._();

  final BarcodeDirectoryDataSource _barcodeDs =
      BarcodeDirectoryDataSource(DatabaseService.instance);

  // ── Reyon (ShelfUnit) ───────────────────────────────────────────────

  Future<int> createUnit({
    required String name,
    required int sections,
    int rows = 1, // ARTIK sabit degil: raflar sutun bazinda dinamik eklenir.
    int? warehouseId,
  }) async {
    final db = await DatabaseService.instance.database;
    return db.insert(AppConstants.shelfUnitTable, {
      'warehouse_id': warehouseId,
      'name': name,
      'sections': sections < 1 ? 1 : sections,
      'rows': rows < 1 ? 1 : rows,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<ShelfUnit?> getUnit(int id) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.shelfUnitTable,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return ShelfUnit.fromMap(rows.first);
  }

  /// Tum reyonlar + urun sayilari (kus bakisi liste). warehouseId verilirse
  /// sadece o depoya baglilar; null verilirse HEPSI.
  Future<List<ShelfUnitSummary>> getUnitSummaries({int? warehouseId}) async {
    final db = await DatabaseService.instance.database;
    final units = await db.query(
      AppConstants.shelfUnitTable,
      where: warehouseId != null ? 'warehouse_id = ?' : null,
      whereArgs: warehouseId != null ? [warehouseId] : null,
      orderBy: 'created_at DESC',
    );
    final result = <ShelfUnitSummary>[];
    for (final u in units) {
      final id = u['id'] as int;
      final cnt = await db.rawQuery(
          'SELECT COUNT(*) c FROM ${AppConstants.shelfSlotTable} WHERE unit_id = ?',
          [id]);
      final count = (cnt.first['c'] as int?) ?? 0;
      final cover = await db.query(
        AppConstants.shelfSlotTable,
        columns: ['photo_path'],
        where: 'unit_id = ? AND photo_path IS NOT NULL',
        whereArgs: [id],
        orderBy: 'section_no ASC, row_no ASC, seq ASC',
        limit: 1,
      );
      result.add(ShelfUnitSummary(
        unit: ShelfUnit.fromMap(u),
        itemCount: count,
        coverPhoto:
            cover.isNotEmpty ? cover.first['photo_path'] as String? : null,
      ));
    }
    return result;
  }

  Future<void> deleteUnit(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.shelfSlotTable,
        where: 'unit_id = ?', whereArgs: [id]);
    await db.delete(AppConstants.shelfUnitTable,
        where: 'id = ?', whereArgs: [id]);
  }

  // ── Urunler (ShelfSlot) ─────────────────────────────────────────────

  /// Belirli bir (bolum, satir) hucresindeki urunler — soldan saga sirali.
  Future<List<ShelfSlot>> getSlotsInCell(
      int unitId, int sectionNo, int rowNo) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.shelfSlotTable,
      where: 'unit_id = ? AND section_no = ? AND row_no = ?',
      whereArgs: [unitId, sectionNo, rowNo],
      orderBy: 'seq ASC, id ASC',
    );
    return rows.map(ShelfSlot.fromMap).toList();
  }

  /// Reyonun TUM urunleri (dizilim ekrani icin) — hucreye/sıraya gore.
  Future<List<ShelfSlot>> getSlots(int unitId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.shelfSlotTable,
      where: 'unit_id = ?',
      whereArgs: [unitId],
      orderBy: 'section_no ASC, row_no ASC, seq ASC, id ASC',
    );
    return rows.map(ShelfSlot.fromMap).toList();
  }

  /// ── DINAMIK RAF (kolon-bazli) ────────────────────────────────────────
  /// Bir sutundaki (section) MEVCUT raflarin numaralari — icinde en az bir
  /// urun olan row_no degerleri, artan sirada. Raf sayisi ONCEDEN sabit
  /// DEGILDIR; her sutun kendi kadar rafa sahip olabilir.
  Future<List<int>> shelfNumbersInColumn(int unitId, int sectionNo) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT row_no FROM ${AppConstants.shelfSlotTable} '
      'WHERE unit_id = ? AND section_no = ? ORDER BY row_no ASC',
      [unitId, sectionNo],
    );
    return rows.map((r) => r['row_no'] as int).toList();
  }

  /// Bir sutuna YENI raf eklemek icin kullanilacak siradaki raf numarasi
  /// (mevcut en buyuk + 1; hic yoksa 1). Bos raf DB'ye yazilmaz; ilk urun
  /// okununca raf fiilen olusur.
  Future<int> nextShelfNumber(int unitId, int sectionNo) async {
    final db = await DatabaseService.instance.database;
    final r = await db.rawQuery(
      'SELECT COALESCE(MAX(row_no), 0) m FROM ${AppConstants.shelfSlotTable} '
      'WHERE unit_id = ? AND section_no = ?',
      [unitId, sectionNo],
    );
    return ((r.first['m'] as int?) ?? 0) + 1;
  }

  /// Bir hucreye urun ekler (sona). Foto verildiyse barkod dizinine de yerel
  /// foto olarak yazilir (uygulama geneli fallback).
  Future<int> addSlot({
    required int unitId,
    required int sectionNo,
    required int rowNo,
    required String barcode,
    String? productName,
    String? photoPath,
  }) async {
    final db = await DatabaseService.instance.database;
    final maxSeq = await db.rawQuery(
      'SELECT COALESCE(MAX(seq), -1) m FROM ${AppConstants.shelfSlotTable} '
      'WHERE unit_id = ? AND section_no = ? AND row_no = ?',
      [unitId, sectionNo, rowNo],
    );
    final nextSeq = ((maxSeq.first['m'] as int?) ?? -1) + 1;

    final id = await db.insert(AppConstants.shelfSlotTable, {
      'unit_id': unitId,
      'section_no': sectionNo,
      'row_no': rowNo,
      'seq': nextSeq,
      'barcode': barcode.trim(),
      'product_name': productName,
      'photo_path': photoPath,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Uygulama geneli fallback: bu barkodun yerel fotografini guncelle.
    if (photoPath != null && photoPath.isNotEmpty) {
      await _barcodeDs.setLocalImage(barcode,
          path: photoPath, productName: productName);
    }
    return id;
  }

  /// Bir slotun fotografini gunceller (yeniden cekim).
  Future<void> updateSlotPhoto(ShelfSlot slot, String photoPath) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.shelfSlotTable,
      {'photo_path': photoPath},
      where: 'id = ?',
      whereArgs: [slot.id],
    );
    await _barcodeDs.setLocalImage(slot.barcode,
        path: photoPath, productName: slot.productName);
  }

  Future<void> deleteSlot(int slotId) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.shelfSlotTable,
        where: 'id = ?', whereArgs: [slotId]);
  }
}
