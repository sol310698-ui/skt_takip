import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ════════════════════════════════════════════════════════════════════
///  ASISTAN "SERBEST MOD" TERCIHI
/// ────────────────────────────────────────────────────────────────────
///  SERBEST MOD AÇIK iken asistan otonom calisir:
///    • Sistemi degistiren kabuk komutlari (pkg install, dosya yazma…)
///      onay kartı BEKLEMEDEN otomatik calisir.
///    • Uretilen EYLEMLER (db_write, shell_exec, palet/urun islemleri…)
///      otomatik ONAYLANIR — kullaniciya sorulmaz, ama kart yine gorunur
///      (ne yapildigi seffaf kalsin).
///
///  TEK ISTISNA (guvenlik kemeri): cihazi geri donusu olmadan bozacak
///  komutlar (rm -rf /, mkfs, dd of=/dev/, fork bombasi, reboot…) yine
///  ENGELLENIR — bkz. TermuxService._blocked. Bu kemeri de kaldirmak
///  istersen o listeyi bosaltmak yeterli.
///
///  Tercih cihazda kalici saklanir; asistan "serbest modu aç/kapat"
///  denince set_free_mode eylemiyle degistirebilir.
/// ════════════════════════════════════════════════════════════════════
class AgentModePrefs {
  AgentModePrefs._();
  static final AgentModePrefs instance = AgentModePrefs._();

  static const _key = 'agent_free_mode';
  final _storage = const FlutterSecureStorage();

  // Acilista bir kez okunup bellekte tutulur (senkron erisim icin).
  bool _freeMode = true; // varsayilan: ACIK (kullanici otonomi istedi)
  bool _loaded = false;

  bool get freeMode => _freeMode;

  /// Uygulama acilisinda bir kez cagrilir; saklanan tercihi yukler.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await _storage.read(key: _key);
      // Kayit yoksa varsayilan ACIK kalir; 'false' yazilmissa kapali.
      if (v != null) _freeMode = v == 'true';
    } catch (_) {
      // okuma hatasi: varsayilan gecerli
    }
    _loaded = true;
  }

  /// Serbest modu degistirir ve kalici olarak yazar.
  Future<void> setFreeMode(bool value) async {
    _freeMode = value;
    try {
      await _storage.write(key: _key, value: value ? 'true' : 'false');
    } catch (_) {
      // yazma basarisiz olsa bile bellekteki deger gecerli kalir
    }
  }
}
