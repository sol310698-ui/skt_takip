import '../constants/app_constants.dart';
import 'database_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  AJAN HAFIZASI (v160)
/// ────────────────────────────────────────────────────────────────────
///  "Benim hatalarımdan beni korusun" isteginin karsiligi.
///
///  Asistan calisirken ogrendiklerini buraya YAZAR (kural/not), sonraki
///  konusmalarda bu notlar baglama eklenir; boylece ayni hata tekrar
///  edilmez. Ornek notlar:
///    • "Palete urun eklerken SKT girilmezse FEFO calismiyor"
///    • "Koli barkodu okutunca urun barkodu turetiliyor, elle girme"
///    • "Fiyat degisiminde urun teshirdeyse ikinci etiket gerekiyor"
///
///  Notlar kategorilere ayrilir; [kind] = 'kural' | 'hata' | 'tercih'.
/// ════════════════════════════════════════════════════════════════════
class AgentMemoryService {
  AgentMemoryService._();
  static final AgentMemoryService instance = AgentMemoryService._();

  /// Not ekler. Ayni metin varsa tekrarlamaz, sadece sayaci artirir.
  Future<void> add(String note, {String kind = 'kural'}) async {
    final db = await DatabaseService.instance.database;
    final t = note.trim();
    if (t.isEmpty) return;
    final existing = await db.query(
      AppConstants.agentMemoryTable,
      where: 'note = ?',
      whereArgs: [t],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      final hits = (existing.first['hits'] as int?) ?? 1;
      await db.update(
        AppConstants.agentMemoryTable,
        {'hits': hits + 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
      return;
    }
    await db.insert(AppConstants.agentMemoryTable, {
      'note': t,
      'kind': kind,
      'hits': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Tum notlar — en cok tekrarlanan (en onemli) once.
  Future<List<Map<String, Object?>>> list({int limit = 100}) async {
    final db = await DatabaseService.instance.database;
    return db.query(
      AppConstants.agentMemoryTable,
      orderBy: 'hits DESC, updated_at DESC',
      limit: limit,
    );
  }

  Future<void> remove(int id) async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.agentMemoryTable,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    final db = await DatabaseService.instance.database;
    await db.delete(AppConstants.agentMemoryTable);
  }

  /// Asistan prompt'una eklenecek kisa metin (en onemli 15 not).
  Future<String> promptBlock() async {
    final rows = await list(limit: 15);
    if (rows.isEmpty) return '';
    final buf = StringBuffer(
        '=== ÖĞRENDİKLERİN (kullanıcıyı hatalardan koru) ===\n');
    for (final r in rows) {
      buf.writeln('- [${r['kind']}] ${r['note']}');
    }
    buf.writeln(
        'Kullanıcı bu notlardaki hatalardan birine yaklaşırsa ÖNCEDEN UYAR.');
    return buf.toString();
  }
}
