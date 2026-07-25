import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'agent_memory_service.dart';
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

  /// Cevaptaki arac cagrilarini ayikla. Bloklar metinden SILINIR.
  ///
  /// TOLERANSLI: model tutarsiz olabiliyor — arac cagrisini bazen ```tool,
  /// bazen ```json, bazen dilsiz ``` blogu icinde yaziyor. Bu yuzden HERHANGI
  /// bir kod blogunu deneriz; icinde "tool" anahtari olan JSON'i arac cagrisi
  /// sayariz (```action blogu "type" icerir, "tool" icermez — dokunmayiz).
  ({String cleanText, List<AgentToolCall> calls}) parse(String reply) {
    final calls = <AgentToolCall>[];

    // 1) Herhangi bir kod blogu: ```<dil>? ... ``` — icinde "tool" varsa al.
    final fence = RegExp(r'```[a-zA-Z0-9_]*\s*([\s\S]*?)```', multiLine: true);
    var clean = reply.replaceAllMapped(fence, (m) {
      final found = _extractToolCalls((m.group(1) ?? '').trim());
      if (found.isEmpty) return m.group(0)!; // arac degil -> blogu KORU
      calls.addAll(found);
      return '';
    }).trim();

    // 2) Kod blogu icinde bulunamadiysa: ciplak JSON nesnesi ({...}) icinde
    //    "tool" ara (model bazen fence koymadan yaziyor).
    if (calls.isEmpty) {
      final bare = RegExp(r'\{[^{}]*"tool"[^{}]*\}');
      clean = clean.replaceAllMapped(bare, (m) {
        final found = _extractToolCalls(m.group(0)!);
        if (found.isEmpty) return m.group(0)!;
        calls.addAll(found);
        return '';
      }).trim();
    }
    return (cleanText: clean, calls: calls);
  }

  /// Ham metni JSON olarak cozup icinden "tool" anahtarli cagrilari toplar.
  List<AgentToolCall> _extractToolCalls(String raw) {
    final out = <AgentToolCall>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic> && e['tool'] != null) {
            out.add(AgentToolCall(e));
          }
        }
      } else if (decoded is Map<String, dynamic> && decoded['tool'] != null) {
        out.add(AgentToolCall(decoded));
      }
    } catch (_) {
      // Bozuk/JSON degil: arac cagrisi yok say.
    }
    return out;
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

  /// Model arac adini tutarsiz yazabiliyor (listApps, shell, apps, uygulamalar).
  /// Adi normalize edip (kucuk harf, harf disi karakterleri at) bilinen bir
  /// takma addan KANONIK araca esler. Eslesme yoksa ham adi dondurur.
  static String _canonicalTool(String raw) {
    final n = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    const map = {
      'dbschema': 'db_schema', 'schema': 'db_schema', 'tables': 'db_schema',
      'tablolar': 'db_schema', 'sema': 'db_schema',
      'dbquery': 'db_query', 'query': 'db_query', 'sql': 'db_query',
      'select': 'db_query', 'sorgu': 'db_query',
      'prefslist': 'prefs_list', 'prefs': 'prefs_list', 'settings': 'prefs_list',
      'ayarlar': 'prefs_list', 'preferences': 'prefs_list',
      'shellrun': 'shell_run', 'shell': 'shell_run', 'run': 'shell_run',
      'bash': 'shell_run', 'sh': 'shell_run', 'terminal': 'shell_run',
      'cmd': 'shell_run', 'command': 'shell_run', 'komut': 'shell_run',
      'exec': 'shell_run', 'runcommand': 'shell_run', 'termux': 'shell_run',
      'readscreen': 'read_screen', 'screen': 'read_screen', 'ekran': 'read_screen',
      'memorylist': 'memory_list', 'memory': 'memory_list', 'notes': 'memory_list',
      'hafiza': 'memory_list', 'notlar': 'memory_list',
      'listapps': 'list_apps', 'apps': 'list_apps', 'app': 'list_apps',
      'applications': 'list_apps', 'uygulamalar': 'list_apps',
      'uygulama': 'list_apps', 'packages': 'list_apps', 'paketler': 'list_apps',
      'paketadlari': 'list_apps', 'getapps': 'list_apps', 'listapp': 'list_apps',
    };
    return map[n] ?? raw.trim();
  }

  Future<String> run(AgentToolCall c) async {
    try {
      // Model arac adini tutarsiz yazabiliyor (listApps, shell, apps...).
      // Kanonik ada esle; boylece "bilinmeyen araç -> tanımlı değil" cikmazi
      // olusmaz.
      switch (_canonicalTool(c.name)) {
        case 'db_schema':
          return _schema(c.args['table']?.toString());
        case 'db_query':
          return _query(
              (c.args['sql'] ?? c.args['query'] ?? '').toString());
        case 'prefs_list':
          return _prefsList(c.args['prefix']?.toString());
        case 'shell_run':
          return _shell(
              (c.args['command'] ?? c.args['cmd'] ?? '').toString(),
              c.args['workdir']?.toString());
        case 'read_screen':
          return _readScreen();
        case 'memory_list':
          return _memoryList();
        case 'list_apps':
          return _listApps(
              (c.args['query'] ?? c.args['filter'] ?? c.args['name'])
                  ?.toString());
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

  /// Termux'ta YALNIZCA zararsiz komut calistirir. Sistemi degistiren
  /// komutlar burada calismaz; onlar icin onay kartli shell_exec eylemi
  /// uretilmelidir.
  Future<String> _shell(String command, String? workdir) async {
    if (command.trim().isEmpty) return '❌ command alanı boş.';
    if (!await TermuxService.instance.isInstalled()) {
      return '❌ Termux kurulu değil. Kabuk komutları kullanılamıyor.';
    }
    final risk = TermuxService.classify(command);
    if (risk != ShellRisk.safe) {
      return '⚠️ Bu komut "${TermuxService.riskLabel(risk)}" sınıfında; '
          'araçla çalıştırılamaz. Gerçekten gerekliyse onay kartı için '
          '```action bloğunda shell_exec kullan.';
    }
    final res = await TermuxService.instance.run(command);
    return res.summary;
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

  /// Kurulu uygulamalari listeler (open_app icin dogru paketi bulmak icin).
  Future<String> _listApps(String? query) async {
    try {
      final apps = await PriceCheckChannel.listApps(query: query);
      if (apps.isEmpty) {
        return (query == null || query.trim().isEmpty)
            ? 'Kurulu uygulama listelenemedi.'
            : '"$query" ile eşleşen kurulu uygulama yok.';
      }
      final buf = StringBuffer('KURULU UYGULAMALAR (${apps.length}):\n');
      for (final a in apps.take(60)) {
        buf.writeln('- ${a.label} → ${a.package}');
      }
      if (apps.length > 60) buf.writeln('… (kısaltıldı)');
      return buf.toString().trim();
    } catch (e) {
      return '❌ Uygulama listesi alınamadı: $e';
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
