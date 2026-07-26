import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_navigator.dart';
import '../services/agent_mode_prefs.dart';
import '../services/agent_tool_service.dart' as ats;
import '../services/assistant_action_service.dart';
import '../services/warehouse_assistant_service.dart';
import '../theme/app_theme.dart';
import 'agent_core.dart';

/// ════════════════════════════════════════════════════════════════════
///  SKT TAKİP ARAÇLARI (function-calling)
/// ────────────────────────────────────────────────────────────────────
///  Mevcut servisleri SARAR — hiçbir yetenek kaybolmaz. Okuma araçları
///  AgentToolService'e, yazma eylemleri AssistantActionService'e gider.
/// ════════════════════════════════════════════════════════════════════

/// Tüm depo/SKT/ürün verisini döndürür (yer, SKT, stok, vardiya, kuyruk).
class WarehouseDataTool extends AgentTool {
  @override
  String get name => 'warehouse_data';
  @override
  String get description =>
      'Depodaki GÜNCEL verinin tamamını döndürür: reyon konumları (ürün→yer), '
      'kayıtlı ürünler, SKT takibi (son kullanma tarihleri, kalan gün), '
      'vardiya durumu ve etiket kuyruğu. "nerede / SKT / stok" sorularından '
      'ÖNCE bunu çağır.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) =>
      WarehouseAssistantService.instance.buildLocalContext();
}

/// Salt-okunur SQL sorgusu.
class DbQueryTool extends AgentTool {
  @override
  String get name => 'db_query';
  @override
  String get description =>
      'Tek bir SELECT/PRAGMA/WITH sorgusu çalıştırır (salt okuma). Sayım, '
      'filtreleme, JOIN, GROUP BY serbest. Değişiklik için app_action kullan.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'sql': {'type': 'string', 'description': 'Tek SELECT sorgusu'}
        },
        'required': ['sql'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) => ats.AgentToolService.instance
      .run(ats.AgentToolCall({'tool': 'db_query', 'sql': args['sql']}));
}

/// Tablo şeması / tablo listesi.
class DbSchemaTool extends AgentTool {
  @override
  String get name => 'db_schema';
  @override
  String get description =>
      'Veritabanı tablolarını (tablo verilmezse) ya da bir tablonun '
      'kolonlarını + örnek satırını verir. SQL yazmadan önce şemayı gör.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'table': {'type': 'string', 'description': 'Tablo adı (opsiyonel)'}
        },
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      ats.AgentToolService.instance.run(ats.AgentToolCall(
          {'tool': 'db_schema', if (args['table'] != null) 'table': args['table']}));
}

/// Termux'ta komut çalıştırır (serbest mod + güvenlik süzgeci AgentToolService'te).
class RunShellTool extends AgentTool {
  @override
  String get name => 'run_shell';
  @override
  String get description =>
      'Telefonda Termux ile Linux komutu çalıştırır (ls, cat, uname, date, '
      'python, pkg install, git, dosya...). Sonucu döndürür. Serbest mod '
      'açıksa sistemi değiştiren komutlar da doğrudan çalışır.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': 'Çalıştırılacak komut'}
        },
        'required': ['command'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) => ats.AgentToolService.instance
      .run(ats.AgentToolCall({'tool': 'shell_run', 'command': args['command']}));
}

/// Kurulu uygulamaları listeler.
class ListAppsTool extends AgentTool {
  @override
  String get name => 'list_apps';
  @override
  String get description =>
      'Telefonda kurulu uygulamaları (ad → paket) listeler; query ile süzülür. '
      'Bir uygulamayı açmadan önce doğru paketi buradan bul.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Ad süzgeci (opsiyonel)'}
        },
      };
  @override
  Future<String> run(Map<String, dynamic> args) =>
      ats.AgentToolService.instance.run(ats.AgentToolCall(
          {'tool': 'list_apps', if (args['query'] != null) 'query': args['query']}));
}

/// Ekrandaki metinleri okur (erişilebilirlik).
class ReadScreenTool extends AgentTool {
  @override
  String get name => 'read_screen';
  @override
  String get description =>
      'Ekranda görünen metinleri okur — nereye dokunacağını bilmek için önce '
      'bunu kullan.';
  @override
  Map<String, dynamic> get parameters =>
      {'type': 'object', 'properties': {}};
  @override
  Future<String> run(Map<String, dynamic> args) => ats.AgentToolService.instance
      .run(ats.AgentToolCall({'tool': 'read_screen'}));
}

/// Sistemde DEĞİŞİKLİK yapan tüm eylemler (tek kapı).
class AppActionTool extends AgentTool {
  static const List<String> _types = [
    'add_pallet_item', 'remove_pallet_item', 'create_pallet', 'delete_pallet',
    'move_pallet', 'create_warehouse', 'create_shelf_unit', 'delete_shelf_unit',
    'add_skt_product', 'update_product', 'dispose_product', 'delete_product',
    'place_shelf_slot', 'create_backup', 'set_theme', 'set_app_lock',
    'change_pin', 'set_biometric', 'set_location_reveal', 'set_company_flow',
    'add_teshir', 'remove_teshir', 'add_restock', 'clear_notifications',
    'set_free_mode', 'open_screen', 'tap_text', 'global_action', 'open_app',
    'shell_exec', 'remember', 'add_barcode_entry', 'add_alarm', 'delete_alarm',
    'db_write', 'prefs_set',
  ];

  @override
  String get name => 'app_action';
  @override
  String get description =>
      'Uygulamada BİR DEĞİŞİKLİK yapar (ürün ekle/güncelle/imha, palet, reyona '
      'yerleştir, yedek al, alarm, tema/kilit, uygulama aç, terminal komutu...). '
      'type = işlem türü, args_json = alanların JSON metni. Örnekler: '
      'add_skt_product {"name":"Süt","barcode":"869...","expiry":"31.12.2026","quantity":3}; '
      'dispose_product {"barcode":"869..."}; '
      'place_shelf_slot {"unit":"Bakliyat","column":2,"row":1,"barcode":"869...","name":"Bulgur"}; '
      'add_pallet_item {"pallet_code":"P123","barcode":"869...","name":"Ketçap","quantity":6}; '
      'open_app {"name":"Termux"}; shell_exec {"command":"pkg install termux-api","description":"kur"}; '
      'create_backup {}; add_alarm {"hour":7,"minute":30,"days":"hergun"}.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'description': 'İşlem türü',
            'enum': _types,
          },
          'args_json': {
            'type': 'string',
            'description': 'İşlem alanları JSON metni (yoksa {})',
          },
        },
        'required': ['type'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    final type = (args['type'] ?? '').toString().trim();
    if (type.isEmpty) return '❌ İşlem türü (type) gerekli.';
    Map<String, dynamic> fields = {};
    final raw = args['args_json'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) fields = Map<String, dynamic>.from(d);
      } catch (_) {
        return '❌ args_json geçerli JSON değil.';
      }
    } else if (raw is Map) {
      fields = Map<String, dynamic>.from(raw);
    }
    return AssistantActionService.instance.runAction({'type': type, ...fields});
  }
}

/// Riskli işlemden önce kullanıcıdan onay. Serbest mod AÇIKSA otomatik onaylar.
class ConfirmTool extends AgentTool {
  @override
  String get name => 'confirm';
  @override
  String get description =>
      'Geri alınamaz/riskli bir işlemden ÖNCE kullanıcı onayı ister '
      '(silme, gönderme, satın alma vb.). "onaylandı" ya da "reddedildi" '
      'döner; "reddedildi" ise işlemi YAPMA.';
  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'message': {
            'type': 'string',
            'description': 'Kullanıcıya gösterilecek onay sorusu'
          }
        },
        'required': ['message'],
      };
  @override
  Future<String> run(Map<String, dynamic> args) async {
    // Serbest mod: onaysız otonom çalışma.
    if (AgentModePrefs.instance.freeMode) return 'onaylandı (serbest mod)';
    final msg = (args['message'] ?? 'Onaylıyor musun?').toString();
    final nav = navigatorKey.currentState;
    if (nav == null) return 'onaylandı';
    final ok = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        title: const Text('Onay gerekli'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Onayla')),
        ],
      ),
    );
    return ok == true ? 'onaylandı' : 'reddedildi';
  }
}

/// Tüm SKT araçlarını ada göre kayıtlar.
Map<String, AgentTool> buildSktTools() {
  final list = <AgentTool>[
    WarehouseDataTool(),
    DbQueryTool(),
    DbSchemaTool(),
    RunShellTool(),
    ListAppsTool(),
    ReadScreenTool(),
    AppActionTool(),
    ConfirmTool(),
  ];
  return {for (final t in list) t.name: t};
}
