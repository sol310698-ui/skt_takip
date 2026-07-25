import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'agent_memory_service.dart';
import 'assistant_auto_prefs.dart';
import 'database_service.dart';
import 'price_check_channel.dart';
import 'termux_service.dart';

/// ════════════════════════════════════════════════════════════════════
///  AGENT ARAC KATMANI (v146)
/// ────────────────────────────────────────────────────────────────────
///  Asistanin SABIT bir ozellik listesine hapsolmamasi icin GENEL AMACLI
///  araclar. Model bunlarla once KESFEDER (hangi tablolar, hangi kolonlar,
///  hangi ayarlar var), sonra okur, gerekirse yazma eylemi onerir.
///
///  Bu sayede "bu ozellik eklenmemis" durumu ortadan kalkar: uygulamanin
///  TUM verisi (SQLite) ve TUM ayarlari (SecureStorage) erisilebilir.
///
///  Guvenlik: OKUMA araclari otomatik calisir (zararsiz). YAZMA islemleri
///  arac olarak DEGIL, onay karti gerektiren ```action bloklari olarak
///  yapilir (bkz. AssistantActionService: db_write / prefs_set).
/// ════════════════════════════════════════════════════════════════════
class AgentToolService {
  AgentToolService._();
  static final AgentToolService instance = AgentToolService._();

  static const int _maxRows = 40;
  static const int _maxChars = 4000;

  /// Cevaptaki araç çağrılarını ayıkla. Doğru biçim ```tool bloğudur, ama
  /// modeller sık sık araç çağrısını YANLIŞLIKLA ```action bloğuna koyar
  /// ({"tool":"shell_run",...}). Bu durumda eskiden "Bilinmeyen işlem"
  /// hatası çıkıyordu. Artık HER iki blok da taranır: içinde "tool" alanı
  /// olan (ve "type" alanı olmayan) JSON bir ARAÇ çağrısıdır; nereye
  /// konursa konsun araç olarak çalıştırılır ve metinden silinir. Gerçek
  /// eylem blokları (```action + "type") dokunulmadan bırakılır.
  ({String cleanText, List<AgentToolCall> calls}) parse(String reply) {
    final calls = <AgentToolCall>[];
    final re = RegExp(r'```(tool|action)\s*([\s\S]*?)```', multiLine: true);
    final clean = reply.replaceAllMapped(re, (m) {
      final fence = m.group(1);
      final raw = (m.group(2) ?? '').trim();
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return m.group(0)!; // bozuk JSON: dokunma
      }
      final entries = <Map<String, dynamic>>[];
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic>) entries.add(e);
        }
      } else if (decoded is Map<String, dynamic>) {
        entries.add(decoded);
      }
      // Bu blok bir ARAÇ çağrısı mı? tool bloğu her zaman; action bloğu
      // ancak tüm girdilerinde "tool" varsa ve hiç "type" yoksa.
      final looksLikeTool = entries.isNotEmpty &&
          entries.every(
              (e) => e.containsKey('tool') && !e.containsKey('type'));
      if (fence == 'tool' || looksLikeTool) {
        for (final e in entries) {
          if (e.containsKey('tool')) calls.add(AgentToolCall(e));
        }
        return ''; // araç: metinden sil
      }
      return m.group(0)!; // gerçek eylem bloğu: dokunma
    }).trim();
    return (cleanText: clean, calls: calls);
  }

  /// Tum arac cagrilarini sirayla calistir; modele geri beslenecek
  /// tek bir metin ureti.
  Future<String> runAll(List<AgentToolCall> calls) async {
    final buf = StringBuffer();
    for (final c in calls) {
      buf.writeln('### ARAÇ: ${c.name}');
      if (c.args.isNotEmpty) {
        final a = Map<String, dynamic>.from(c.args)..remove('tool');
        if (a.isNotEmpty) buf.writeln('Girdi: ${jsonEncode(a)}');
      }
      final out = await run(c);
      buf.writeln(out.length > _maxChars
          ? '${out.substring(0, _maxChars)}\n…(kısaltıldı)'
          : out);
      buf.writeln();
    }
    return buf.toString().trim();
  }

  Future<String> run(AgentToolCall c) async {
    try {
      switch (c.name) {
        case 'db_schema':
          return _schema(c.args['table']?.toString());
        case 'db_query':
          return _query(c.args['sql']?.toString() ?? '');
        case 'prefs_list':
          return _prefsList(c.args['prefix']?.toString());
        case 'shell_run':
          return _shell(c.args['command']?.toString() ?? '',
              c.args['workdir']?.toString());
        case 'read_screen':
          return _readScreen();
        case 'memory_list':
          return _memoryList();
        case 'list_apps':
          return _listApps(c.args['filter']?.toString());
        default:
          return '❌ Bilinmeyen araç: "${c.name}". '
              'Kullanılabilir: db_schema, db_query, prefs_list, '
              'shell_run, read_screen, memory_list, list_apps.';
      }
    } catch (e) {
      return '❌ Araç hatası: $e';
    }
  }

  // ── KABUK / EKRAN / HAFIZA ARACLARI (v160) ─────────────────────────

  /// Termux'ta komut calistirir. UCU ACIK kullanim: OTOMATIK MOD acikken
  /// sistemi degistiren komutlar da (pkg install, dosya yazma, git...) onay
  /// beklemeden calisir — boylece ajan eksik araci kurup kendi kendine
  /// ilerleyebilir. Yalnizca cihazi bozabilecek YIKICI komutlar (rm -rf /,
  /// mkfs, dd of=/dev/, fork bombasi, reboot...) her kosulda engellidir.
  /// Otomatik mod KAPALIYKEN sistemi degistiren komutlar yine onay ister
  /// (shell_exec eylemi).
  Future<String> _shell(String command, String? workdir) async {
    if (command.trim().isEmpty) return '❌ command alanı boş.';
    if (!await TermuxService.instance.isInstalled()) {
      return '❌ Termux kurulu değil. Kabuk komutları kullanılamıyor.';
    }
    final auto = AssistantAutoPrefs.instance.auto;
    final res = await TermuxService.instance
        .run(command, workdir: workdir, allowSystemChange: auto);
    return res.summary;
  }

  /// Yuklu uygulamalari listeler — TERMUX GEREKTIRMEZ (native).
  /// [filter] verilirse ada/pakete gore suzer ("whats" -> WhatsApp).
  Future<String> _listApps(String? filter) async {
    final apps = await PriceCheckChannel.listInstalledApps();
    if (apps.isEmpty) {
      return 'Yüklü uygulama listesi okunamadı.';
    }
    var list = apps;
    final f = filter?.trim().toLowerCase() ?? '';
    if (f.isNotEmpty) {
      list = apps
          .where((a) =>
              (a['label'] ?? '').toLowerCase().contains(f) ||
              (a['package'] ?? '').toLowerCase().contains(f))
          .toList();
    }
    if (list.isEmpty) return 'Eşleşen uygulama yok ("$filter").';
    final shown = list.take(200).toList();
    final buf = StringBuffer('YÜKLÜ UYGULAMALAR (${list.length}'
        '${list.length > 200 ? ', ilk 200' : ''}):\n');
    for (final a in shown) {
      buf.writeln('- ${a['label']} [${a['package']}]');
    }
    return buf.toString().trim();
  }

  /// Ekranda ne yazdigini okur (ajan ne gordugunu bilsin).
  Future<String> _readScreen() async {
    try {
      final txt = await PriceCheckChannel.agentReadScreen();
      if (txt.trim().isEmpty) {
        return 'Ekran okunamadı (erişilebilirlik servisi kapalı olabilir).';
      }
      return 'EKRANDAKİ METİNLER:\n$txt';
    } catch (e) {
      return '❌ Ekran okunamadı: $e';
    }
  }

  /// Daha once ogrenilen kurallar/hatalar.
  Future<String> _memoryList() async {
    final rows = await AgentMemoryService.instance.list(limit: 40);
    if (rows.isEmpty) return 'Henüz öğrenilmiş not yok.';
    final buf = StringBuffer('ÖĞRENİLEN NOTLAR (${rows.length}):\n');
    for (final r in rows) {
      buf.writeln('- [${r['kind']}] ${r['note']} (${r['hits']}×)');
    }
    return buf.toString().trim();
  }

  // ── OKUMA ARACLARI ─────────────────────────────────────────────────

  /// Tablo listesi (tablo verilmezse) ya da tek tablonun kolonlari.
  Future<String> _schema(String? table) async {
    final db = await DatabaseService.instance.database;
    if (table == null || table.trim().isEmpty) {
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final names = rows.map((r) => r['name']).toList();
      final buf = StringBuffer('Tablolar (${names.length}):\n');
      for (final n in names) {
        final c = await db.rawQuery('SELECT COUNT(*) c FROM "$n"');
        buf.writeln('- $n (${c.first['c']} kayıt)');
      }
      return buf.toString().trim();
    }
    final t = table.trim();
    final cols = await db.rawQuery('PRAGMA table_info("$t")');
    if (cols.isEmpty) return '❌ "$t" adlı tablo yok.';
    final buf = StringBuffer('$t kolonları:\n');
    for (final c in cols) {
      buf.writeln('- ${c['name']} (${c['type']})'
          '${(c['pk'] as int? ?? 0) > 0 ? ' [PK]' : ''}'
          '${(c['notnull'] as int? ?? 0) > 0 ? ' [NOT NULL]' : ''}');
    }
    // Ornek satir: kolonlarin nasil doldugunu gormek modele cok yardimci.
    final sample = await db.rawQuery('SELECT * FROM "$t" LIMIT 2');
    if (sample.isNotEmpty) {
      buf.writeln('Örnek satır(lar):');
      for (final r in sample) {
        buf.writeln(jsonEncode(r));
      }
    }
    return buf.toString().trim();
  }

  /// SADECE okuma sorgusu. INSERT/UPDATE/DELETE burada CALISMAZ.
  Future<String> _query(String sql) async {
    final q = sql.trim().replaceAll(RegExp(r';\s*$'), '');
    if (q.isEmpty) return '❌ sql alanı boş.';
    final lower = q.toLowerCase();
    if (!(lower.startsWith('select') || lower.startsWith('pragma') ||
        lower.startsWith('with'))) {
      return '❌ db_query yalnızca SELECT/PRAGMA/WITH kabul eder. '
          'Değişiklik için ```action bloğu ile db_write kullan.';
    }
    if (q.contains(';')) return '❌ Tek sorgu gönder (";" kullanma).';
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(q);
    if (rows.isEmpty) return 'Sonuç: 0 satır.';
    final shown = rows.take(_maxRows).toList();
    final buf = StringBuffer('Sonuç: ${rows.length} satır'
        '${rows.length > _maxRows ? ' (ilk $_maxRows gösteriliyor)' : ''}\n');
    for (final r in shown) {
      buf.writeln(jsonEncode(r));
    }
    return buf.toString().trim();
  }

  /// Uygulamanin TUM ayarlari (FlutterSecureStorage). Tema, kilit, akis
  /// tercihleri, model secimi… hepsi burada gorunur.
  Future<String> _prefsList(String? prefix) async {
    const storage = FlutterSecureStorage();
    final all = await storage.readAll();
    final keys = all.keys.toList()..sort();
    final buf = StringBuffer();
    var n = 0;
    for (final k in keys) {
      if (prefix != null &&
          prefix.trim().isNotEmpty &&
          !k.toLowerCase().contains(prefix.trim().toLowerCase())) {
        continue;
      }
      // Guvenlik: sir niteligindeki degerleri maskele.
      final masked = _isSecret(k) ? '***' : (all[k] ?? '');
      buf.writeln('- $k = $masked');
      n++;
    }
    if (n == 0) return 'Eşleşen ayar yok.';
    return 'Ayarlar ($n):\n${buf.toString().trim()}';
  }

  static bool _isSecret(String key) {
    final k = key.toLowerCase();
    return k.contains('pin') ||
        k.contains('password') ||
        k.contains('api_key') ||
        k.contains('apikey') ||
        k.contains('token') ||
        k.contains('secret');
  }
}

/// Tek bir arac cagrisi.
class AgentToolCall {
  final Map<String, dynamic> args;
  const AgentToolCall(this.args);
  String get name => (args['tool'] ?? '').toString().trim();
}
