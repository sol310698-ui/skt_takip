import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  Fiyat Degisim — Oturum tabanli model + servis
/// ════════════════════════════════════════════════════════════════════

/// Bir fiyat degisim oturumu (genelde bir gun / bir imzali is).
class PriceChangeSession {
  final int? id;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String status; // 'active' | 'completed'
  final int a4Count;
  final List<String> a4Photos; // cekilen A4 fotograflarinin kalici yollari

  const PriceChangeSession({
    this.id,
    required this.createdAt,
    this.completedAt,
    this.status = 'active',
    this.a4Count = 0,
    this.a4Photos = const [],
  });

  bool get isCompleted => status == 'completed';

  factory PriceChangeSession.fromMap(Map<String, Object?> m) {
    List<String> photos = [];
    final raw = m['a4_photos'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        photos = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {}
    }
    return PriceChangeSession(
      id: m['id'] as int?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      completedAt: m['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['completed_at'] as int)
          : null,
      status: (m['status'] as String?) ?? 'active',
      a4Count: (m['a4_count'] as int?) ?? 0,
      a4Photos: photos,
    );
  }
}

/// Oturum + kalem istatistikleri (kart gosterimi icin).
class SessionSummary {
  final PriceChangeSession session;
  final int total;
  final int changed;
  const SessionSummary(
      {required this.session, required this.total, required this.changed});
  int get pending => total - changed;
  double get progress => total == 0 ? 0 : changed / total;
}

/// Fiyat degisim listesi kalemi.
class PriceChangeItem {
  final int? id;
  final String batchId; // kaynak: 'gemini' | 'mlkit' | 'manual'
  final int sessionId;
  final String barcode;
  final String? productName;
  final double? newPrice;
  final double? oldPrice;
  final String? aisle;
  final DateTime createdAt;
  final bool changed;
  final DateTime? changedAt;
  final String? photoPath; // degisim kaniti (kalici yol)

  const PriceChangeItem({
    this.id,
    required this.batchId,
    this.sessionId = 0,
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
    int? id,
    int? sessionId,
    String? productName,
    double? newPrice,
    double? oldPrice,
    String? aisle,
    bool? changed,
    DateTime? changedAt,
    String? photoPath,
  }) =>
      PriceChangeItem(
        id: id ?? this.id,
        batchId: batchId,
        sessionId: sessionId ?? this.sessionId,
        barcode: barcode,
        productName: productName ?? this.productName,
        newPrice: newPrice ?? this.newPrice,
        oldPrice: oldPrice ?? this.oldPrice,
        aisle: aisle ?? this.aisle,
        createdAt: createdAt,
        changed: changed ?? this.changed,
        changedAt: changedAt ?? this.changedAt,
        photoPath: photoPath ?? this.photoPath,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'batch_id': batchId,
        'session_id': sessionId,
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
        batchId: (m['batch_id'] as String?) ?? '',
        sessionId: (m['session_id'] as int?) ?? 0,
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

/// ML Kit fallback parser (Gemini yoksa).
class PriceChangeParser {
  static final RegExp _barcode = RegExp(r'\b(\d{12,13})\b');
  static final RegExp _price = RegExp(r'\d{1,4}(?:[.,]\d{1,2})?');

  static List<PriceChangeItem> parse(String ocrText, int sessionId) {
    final now = DateTime.now();
    final items = <PriceChangeItem>[];
    final seen = <String>{};

    final lines = ocrText.split(RegExp(r'[\r\n]+'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.length < 12) continue;

      final bcMatch = _barcode.firstMatch(line);
      if (bcMatch == null) continue;
      final barcode = bcMatch.group(1)!;
      if (seen.contains(barcode)) continue;
      seen.add(barcode);

      final after = line.substring(bcMatch.end).trim();

      String? aisle;
      final aisleMatch =
          RegExp(r'([A-ZÇĞİÖŞÜ]{2,}\s*-\s*[A-ZÇĞİÖŞÜ ]{3,})$')
              .firstMatch(after);
      if (aisleMatch != null) aisle = aisleMatch.group(1)?.trim();

      final beforeAisle = aisleMatch != null
          ? after.substring(0, aisleMatch.start)
          : after;
      final prices = _price
          .allMatches(beforeAisle)
          .map((m) => m.group(0)!)
          .where(
              (s) => s.contains(',') || s.contains('.') || s.length >= 3)
          .toList();

      double? newPrice;
      double? oldPrice;
      if (prices.length >= 2) {
        newPrice = _toDouble(prices[prices.length - 2]);
        oldPrice = _toDouble(prices[prices.length - 1]);
      } else if (prices.length == 1) {
        newPrice = _toDouble(prices[0]);
      }

      String? name;
      final nameMatch = RegExp(
              r'^([A-Za-zÇĞİÖŞÜçğıöşü0-9\.\-\(\) ]{3,}?)(?=\s+\d|\*|$)')
          .firstMatch(after);
      if (nameMatch != null) {
        name = nameMatch.group(1)?.replaceAll(RegExp(r'\*+'), '').trim();
        if (name != null && name.length < 3) name = null;
      }

      items.add(PriceChangeItem(
        batchId: 'mlkit',
        sessionId: sessionId,
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

/// ════════════════════════════════════════════════════════════════════
///  Servis
/// ════════════════════════════════════════════════════════════════════
class PriceChangeService {
  PriceChangeService._();
  static final PriceChangeService instance = PriceChangeService._();

  // ── Kalici fotograf deposu ──────────────────────────────────────────
  /// Gecici (kamera) fotografi uygulamanin kalici klasorune kopyalar.
  /// Kanitlar boylece sistem temizliginde kaybolmaz.
  Future<String> persistPhoto(String tempPath, String prefix) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/price_proofs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dst = File('${dir.path}/$name');
    await File(tempPath).copy(dst.path);
    return dst.path;
  }

  // ── Oturumlar ──────────────────────────────────────────────────────
  Future<int> createSession() async {
    final db = await DatabaseService.instance.database;
    return db.insert(AppConstants.priceChangeSessionTable, {
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'active',
      'a4_count': 0,
      'a4_photos': '[]',
    });
  }

  Future<List<SessionSummary>> getSessions() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.priceChangeSessionTable,
      orderBy: 'created_at DESC',
      limit: 30,
    );
    final result = <SessionSummary>[];
    for (final r in rows) {
      final s = PriceChangeSession.fromMap(r);
      final counts = await _counts(s.id!);
      result.add(
          SessionSummary(session: s, total: counts.$1, changed: counts.$2));
    }
    return result;
  }

  Future<PriceChangeSession?> getSession(int id) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(AppConstants.priceChangeSessionTable,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return PriceChangeSession.fromMap(rows.first);
  }

  Future<(int, int)> _counts(int sessionId) async {
    final db = await DatabaseService.instance.database;
    final total = (await db.rawQuery(
            'SELECT COUNT(*) c FROM ${AppConstants.priceChangeTable} WHERE session_id = ?',
            [sessionId]))
        .first['c'] as int;
    final changed = (await db.rawQuery(
            'SELECT COUNT(*) c FROM ${AppConstants.priceChangeTable} WHERE session_id = ? AND changed = 1',
            [sessionId]))
        .first['c'] as int;
    return (total, changed);
  }

  /// Oturuma A4 ekle: fotografi kalici yap, sayaci artir, kalemleri yaz.
  /// Ayni barkod oturumda varsa atlanir. Donen: eklenen kalem sayisi.
  Future<int> addA4ToSession({
    required int sessionId,
    required String tempPhotoPath,
    required List<PriceChangeItem> items,
  }) async {
    final db = await DatabaseService.instance.database;

    final permanent = await persistPhoto(tempPhotoPath, 'a4_s$sessionId');

    final session = await getSession(sessionId);
    if (session != null) {
      final photos = [...session.a4Photos, permanent];
      await db.update(
        AppConstants.priceChangeSessionTable,
        {'a4_count': session.a4Count + 1, 'a4_photos': jsonEncode(photos)},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    }

    final existing = await getItems(sessionId);
    final codes = existing.map((e) => e.barcode).toSet();
    final batch = db.batch();
    int added = 0;
    for (final item in items) {
      if (codes.contains(item.barcode)) continue;
      codes.add(item.barcode);
      batch.insert(AppConstants.priceChangeTable,
          item.copyWith(sessionId: sessionId).toMap()..remove('id'));
      added++;
    }
    await batch.commit(noResult: true);
    return added;
  }

  /// Oturuma kalem ekle — FOTOGRAFSIZ (Excel ice aktarma vb. icin).
  /// A4 sayaci/fotograf listesine dokunmaz. Cift barkod atlanir.
  Future<int> addItemsToSession(
      int sessionId, List<PriceChangeItem> items) async {
    final db = await DatabaseService.instance.database;
    final existing = await getItems(sessionId);
    final codes = existing.map((e) => e.barcode).toSet();
    final batch = db.batch();
    int added = 0;
    for (final item in items) {
      if (codes.contains(item.barcode)) continue;
      codes.add(item.barcode);
      batch.insert(AppConstants.priceChangeTable,
          item.copyWith(sessionId: sessionId).toMap()..remove('id'));
      added++;
    }
    await batch.commit(noResult: true);
    return added;
  }

  /// Barkod+ad ciftlerini barkod dizinine ekler (yoksa).
  /// Boylece sonraki aramalarda internete (OFF) gerek kalmaz; DB zenginlesir.
  /// Mevcut kaydı KORUR (ignore), uzerine yazmaz. Donen: yeni eklenen sayisi.
  Future<int> enrichDirectory(List<PriceChangeItem> items) async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    int added = 0;
    final batch = db.batch();
    final seen = <String>{};
    for (final item in items) {
      final name = item.productName?.trim();
      final bc = item.barcode.trim();
      // Ad yoksa dizine eklenemez (product_name NOT NULL).
      if (name == null || name.isEmpty || bc.isEmpty) continue;
      if (seen.contains(bc)) continue;
      seen.add(bc);
      batch.insert(
        AppConstants.barcodeTable,
        {'barcode': bc, 'product_name': name, 'imported_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore, // mevcut kaydi koru
      );
      added++;
    }
    await batch.commit(noResult: true);
    return added;
  }

  Future<List<PriceChangeItem>> getItems(int sessionId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.priceChangeTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'changed ASC, aisle ASC, created_at ASC',
    );
    return rows.map(PriceChangeItem.fromMap).toList();
  }

  Future<PriceChangeItem?> findInSession(
      int sessionId, String barcode) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.priceChangeTable,
      where: 'session_id = ? AND barcode = ?',
      whereArgs: [sessionId, barcode.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PriceChangeItem.fromMap(rows.first);
  }

  /// Kalemi degistirildi isaretle; kanit fotografini KALICI klasore tasir.
  Future<void> markChanged(int id, String tempPhotoPath) async {
    final permanent = await persistPhoto(tempPhotoPath, 'proof_$id');
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.priceChangeTable,
      {
        'changed': 1,
        'changed_at': DateTime.now().millisecondsSinceEpoch,
        'photo_path': permanent,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> completeSession(int sessionId) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.priceChangeSessionTable,
      {
        'status': 'completed',
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Oturumu ve kalemlerini sil (kanit fotograflari diskte kalir).
  Future<void> deleteSession(int sessionId) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.priceChangeTable,
        where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete(AppConstants.priceChangeSessionTable,
        where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<int> upsertItem(PriceChangeItem item) async {
    final db = await DatabaseService.instance.database;
    if (item.id != null) {
      await db.update(AppConstants.priceChangeTable, item.toMap(),
          where: 'id = ?', whereArgs: [item.id]);
      return item.id!;
    }
    return db.insert(
        AppConstants.priceChangeTable, item.toMap()..remove('id'));
  }

  Future<void> deleteItem(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.priceChangeTable,
        where: 'id = ?', whereArgs: [id]);
  }
}
