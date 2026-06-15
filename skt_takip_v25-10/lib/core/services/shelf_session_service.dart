import '../constants/app_constants.dart';
import '../services/database_service.dart';

/// Reyon kontrol oturumu istatistikleri.
class ShelfSession {
  final int? id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int scannedCount;
  final int matchCount;
  final int mismatchCount;
  final int priceDiffCount;
  final int noPriceCount;

  const ShelfSession({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.scannedCount = 0,
    this.matchCount = 0,
    this.mismatchCount = 0,
    this.priceDiffCount = 0,
    this.noPriceCount = 0,
  });

  ShelfSession copyWith({
    int? scannedCount,
    int? matchCount,
    int? mismatchCount,
    int? priceDiffCount,
    int? noPriceCount,
    DateTime? endedAt,
  }) =>
      ShelfSession(
        id: id,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        scannedCount: scannedCount ?? this.scannedCount,
        matchCount: matchCount ?? this.matchCount,
        mismatchCount: mismatchCount ?? this.mismatchCount,
        priceDiffCount: priceDiffCount ?? this.priceDiffCount,
        noPriceCount: noPriceCount ?? this.noPriceCount,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'scanned_count': scannedCount,
        'match_count': matchCount,
        'mismatch_count': mismatchCount,
        'price_diff_count': priceDiffCount,
        'no_price_count': noPriceCount,
      };

  factory ShelfSession.fromMap(Map<String, Object?> m) => ShelfSession(
        id: m['id'] as int?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int)
            : null,
        scannedCount: (m['scanned_count'] as int?) ?? 0,
        matchCount: (m['match_count'] as int?) ?? 0,
        mismatchCount: (m['mismatch_count'] as int?) ?? 0,
        priceDiffCount: (m['price_diff_count'] as int?) ?? 0,
        noPriceCount: (m['no_price_count'] as int?) ?? 0,
      );

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);
  int get totalIssues => mismatchCount + priceDiffCount;
}

/// Reyon kontrol oturumu kayit servisi.
class ShelfSessionService {
  ShelfSessionService._();
  static final ShelfSessionService instance = ShelfSessionService._();

  ShelfSession? _current;
  ShelfSession? get current => _current;
  bool get hasSession => _current != null;

  /// Yeni oturum baslatir.
  Future<void> start() async {
    final now = DateTime.now();
    final db = await DatabaseService.instance.database;
    final id = await db.insert(
      AppConstants.shelfSessionTable,
      {
        'started_at': now.millisecondsSinceEpoch,
        'scanned_count': 0,
        'match_count': 0,
        'mismatch_count': 0,
        'price_diff_count': 0,
        'no_price_count': 0,
      },
    );
    _current = ShelfSession(id: id, startedAt: now);
  }

  /// Mevcut oturuma etiket tarama sonucu ekler.
  void record({
    bool matched = false,
    bool mismatched = false,
    bool priceDiff = false,
    bool noPrice = false,
  }) {
    if (_current == null) return;
    _current = _current!.copyWith(
      scannedCount: _current!.scannedCount + 1,
      matchCount: _current!.matchCount + (matched ? 1 : 0),
      mismatchCount: _current!.mismatchCount + (mismatched ? 1 : 0),
      priceDiffCount: _current!.priceDiffCount + (priceDiff ? 1 : 0),
      noPriceCount: _current!.noPriceCount + (noPrice ? 1 : 0),
    );
  }

  /// Oturumu kapatir ve DB'ye yazar. Tamamlanmis oturumu dondurur.
  Future<ShelfSession?> finish() async {
    if (_current == null || _current!.id == null) return null;
    final finished = _current!.copyWith(endedAt: DateTime.now());
    final db = await DatabaseService.instance.database;
    await db.update(
      AppConstants.shelfSessionTable,
      finished.toMap(),
      where: 'id = ?',
      whereArgs: [finished.id],
    );
    _current = null;
    return finished;
  }

  /// Son N oturumu dondurur (gecmis rapor icin).
  Future<List<ShelfSession>> getRecent({int limit = 20}) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      AppConstants.shelfSessionTable,
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(ShelfSession.fromMap).toList();
  }
}

