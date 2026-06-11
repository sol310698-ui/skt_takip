import '../constants/app_constants.dart';
import 'database_service.dart';

/// Fiyat degisim listesi kalemi (imzali A4 sayfasindan OCR ile cikarilan satir).
class PriceChangeItem {
  final int? id;
  final String batchId;       // ayni A4 yuklemesini gruplar (tarih-zaman damgasi)
  final String barcode;
  final String? productName;
  final double? newPrice;     // Fiyati
  final double? oldPrice;     // Eski Fiyati
  final String? aisle;        // Reyonu
  final DateTime createdAt;

  // Reyon uygulama durumu
  final bool changed;         // etiket degistirildi mi
  final DateTime? changedAt;
  final String? photoPath;    // degisim kaniti fotografi

  const PriceChangeItem({
    this.id,
    required this.batchId,
    required this.barcode,
    this.productName,
    this.newPrice,
    this.oldPrice,
    this.aisle,
    required this.createdAt,
    this.changed = false,
    this.changedAt,
    this.photoPath,
  });

  PriceChangeItem copyWith({
    bool? changed,
    DateTime? changedAt,
    String? photoPath,
  }) =>
      PriceChangeItem(
        id: id,
        batchId: batchId,
        barcode: barcode,
        productName: productName,
        newPrice: newPrice,
        oldPrice: oldPrice,
        aisle: aisle,
        createdAt: createdAt,
        changed: changed ?? this.changed,
        changedAt: changedAt ?? this.changedAt,
        photoPath: photoPath ?? this.photoPath,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'batch_id': batchId,
        'barcode': barcode,
        'product_name': productName,
        'new_price': newPrice,
        'old_price': oldPrice,
        'aisle': aisle,
        'created_at': createdAt.millisecondsSinceEpoch,
        'changed': changed ? 1 : 0,
        'changed_at': changedAt?.millisecondsSinceEpoch,
        'photo_path': photoPath,
      };

  factory PriceChangeItem.fromMap(Map<String, Object?> m) => PriceChangeItem(
        id: m['id'] as int?,
        batchId: m['batch_id'] as String,
        barcode: m['barcode'] as String,
        productName: m['product_name'] as String?,
        newPrice: (m['new_price'] as num?)?.toDouble(),
        oldPrice: (m['old_price'] as num?)?.toDouble(),
        aisle: m['aisle'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        changed: (m['changed'] as int? ?? 0) == 1,
        changedAt: m['changed_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['changed_at'] as int)
            : null,
        photoPath: m['photo_path'] as String?,
      );
}

/// A4 OCR metnini satirlara ayirip fiyat degisim kalemlerine cevirir.
class PriceChangeParser {
  /// 8-13 haneli barkod (anchor). Satir basinda ya da metin icinde.
  static final RegExp _barcode = RegExp(r'\b(\d{8,13})\b');
  /// Fiyat: 44,95 / 199,9 / 1199 / 76.95 gibi.
  static final RegExp _price = RegExp(r'\d{1,4}(?:[.,]\d{1,2})?');

  /// OCR ham metnini parse eder. Her satirda bir barkod arar; bulursa
  /// satirin kalanindan ad, fiyatlar ve reyonu cikarmaya calisir.
  static List<PriceChangeItem> parse(String ocrText, String batchId) {
    final now = DateTime.now();
    final items = <PriceChangeItem>[];
    final seen = <String>{};

    final lines = ocrText.split(RegExp(r'[\r\n]+'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.length < 8) continue;

      final bcMatch = _barcode.firstMatch(line);
      if (bcMatch == null) continue;
      final barcode = bcMatch.group(1)!;
      // 8-13 hane disindakileri (stok kodu vb.) ele.
      if (barcode.length < 12) continue; // gercek barkodlar 12-13 hane
      if (seen.contains(barcode)) continue;
      seen.add(barcode);

      // Barkoddan sonraki kisim: ad + kodlar + fiyatlar + reyon.
      final after = line.substring(bcMatch.end).trim();

      // Reyonu: "ANPA - ATISTIRMALIK" gibi son buyuk-harf bloku.
      String? aisle;
      final aisleMatch =
          RegExp(r'([A-ZÇĞİÖŞÜ]{2,}\s*-\s*[A-ZÇĞİÖŞÜ ]{3,})$').firstMatch(after);
      if (aisleMatch != null) {
        aisle = aisleMatch.group(1)?.trim();
      }

      // Fiyatlar: reyon oncesi tum sayilar. Son iki fiyat = yeni, eski.
      final beforeAisle = aisleMatch != null
          ? after.substring(0, aisleMatch.start)
          : after;
      final prices = _price
          .allMatches(beforeAisle)
          .map((m) => m.group(0)!)
          .where((s) => s.contains(',') || s.contains('.') || s.length >= 3)
          .toList();

      double? newPrice;
      double? oldPrice;
      if (prices.length >= 2) {
        newPrice = _toDouble(prices[prices.length - 2]);
        oldPrice = _toDouble(prices[prices.length - 1]);
      } else if (prices.length == 1) {
        newPrice = _toDouble(prices[0]);
      }

      // Urun adi: barkoddan sonraki ilk harf blogu (fiyat/koddan once).
      String? name;
      final nameMatch =
          RegExp(r'^([A-Za-zÇĞİÖŞÜçğıöşü0-9\.\-\(\) ]{3,}?)(?=\s+\d|\*|$)')
              .firstMatch(after);
      if (nameMatch != null) {
        name = nameMatch.group(1)?.replaceAll(RegExp(r'\*+'), '').trim();
        if (name != null && name.length < 3) name = null;
      }

      items.add(PriceChangeItem(
        batchId: batchId,
        barcode: barcode,
        productName: name,
        newPrice: newPrice,
        oldPrice: oldPrice,
        aisle: aisle,
        createdAt: now,
      ));
    }
    return items;
  }

  static double? _toDouble(String s) {
    final norm = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(norm);
  }
}

/// Fiyat degisim listesi servisi: kaydet, sorgula, isaretle, rapor.
class PriceChangeService {
  PriceChangeService._();
  static final PriceChangeService instance = PriceChangeService._();

  /// Bugune ait kalemleri ekler (BIRDEN FAZLA A4 birikir).
  /// Ayni barkod bugun zaten varsa tekrar eklemez (cift okuma korumasi).
  /// Donen: eklenen yeni kalem sayisi.
  Future<int> addToToday(List<PriceChangeItem> items) async {
    final db = await DatabaseService.instance.database;
    final existing = await getActiveBatch();
    final existingCodes = existing.map((e) => e.barcode).toSet();

    final batch = db.batch();
    int added = 0;
    for (final item in items) {
      if (existingCodes.contains(item.barcode)) continue; // zaten var
      existingCodes.add(item.barcode);
      batch.insert(AppConstants.priceChangeTable,
          item.toMap()..remove('id'));
      added++;
    }
    await batch.commit(noResult: true);
    return added;
  }

  /// Bugun (00:00 sonrasi) eklenen TUM kalemleri dondurur — coklu A4 birlikte.
  Future<List<PriceChangeItem>> getActiveBatch() async {
    final db = await DatabaseService.instance.database;
    final startOfDay = DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day)
        .millisecondsSinceEpoch;
    final rows = await db.query(
      AppConstants.priceChangeTable,
      where: 'created_at >= ?',
      whereArgs: [startOfDay],
      orderBy: 'changed ASC, aisle ASC, created_at ASC',
    );
    return rows.map(PriceChangeItem.fromMap).toList();
  }

  /// Barkodu aktif batch icinde ara.
  Future<PriceChangeItem?> findInActiveBatch(String barcode) async {
    final items = await getActiveBatch();
    for (final i in items) {
      if (i.barcode == barcode) return i;
    }
    return null;
  }

  /// Bir kalemi "degistirildi" olarak isaretle (foto yolu ile).
  Future<void> markChanged(int id, String photoPath) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.priceChangeTable,
      {
        'changed': 1,
        'changed_at': DateTime.now().millisecondsSinceEpoch,
        'photo_path': photoPath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Bugune ait TUM kalemleri sil (yeni gun / sifirlama).
  Future<void> clearActiveBatch() async {
    final db = await DatabaseService.instance.database;
    final startOfDay = DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day)
        .millisecondsSinceEpoch;
    await db.delete(
      AppConstants.priceChangeTable,
      where: 'created_at >= ?',
      whereArgs: [startOfDay],
    );
  }

  /// Manuel kalem ekle/duzelt (OCR hatasi duzeltmesi icin).
  Future<int> upsertItem(PriceChangeItem item) async {
    final db = await DatabaseService.instance.database;
    if (item.id != null) {
      await db.update(AppConstants.priceChangeTable, item.toMap(),
          where: 'id = ?', whereArgs: [item.id]);
      return item.id!;
    }
    return db.insert(AppConstants.priceChangeTable,
        item.toMap()..remove('id'));
  }

  /// Bir kalemi sil.
  Future<void> deleteItem(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.priceChangeTable,
        where: 'id = ?', whereArgs: [id]);
  }
}
