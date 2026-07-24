import 'package:flutter/services.dart';

/// Bir kabuk komutunun guvenlik sinifi.
enum ShellRisk {
  /// Zararsiz okuma/kurulum — onaysiz calisabilir.
  safe,

  /// Sistemi degistirir — KULLANICI ONAYI ister.
  needsConfirm,

  /// Geri donusu olmayan/yikici — HIC calistirilmaz.
  blocked,
}

class ShellResult {
  final bool ok;
  final String stdout;
  final String stderr;
  final int exitCode;
  final String? error;
  const ShellResult({
    required this.ok,
    this.stdout = '',
    this.stderr = '',
    this.exitCode = -1,
    this.error,
  });

  /// Modele/kullaniciya gosterilecek kisa ozet.
  String get summary {
    if (error != null && error!.isNotEmpty) return '❌ $error';
    final out = stdout.trim();
    final err = stderr.trim();
    final buf = StringBuffer();
    if (out.isNotEmpty) buf.writeln(out);
    if (err.isNotEmpty) buf.writeln('[stderr] $err');
    buf.write('(çıkış kodu: $exitCode)');
    return buf.toString();
  }
}

/// ════════════════════════════════════════════════════════════════════
///  TERMUX KABUK SERVISI (v160)
/// ────────────────────────────────────────────────────────────────────
///  Asistanin telefonda komut calistirmasini saglar — paket kurar,
///  script yazar, log okur. GUVENLIK KATMANI burada:
///
///   • blocked  : cihazi bozabilecek komutlar (rm -rf /, mkfs, dd, fork
///                bombasi, reboot...) HICBIR KOSULDA calismaz.
///   • needsConfirm: sistemi degistirenler (pkg install, rm, mv, chmod,
///                git push...) ONAY KARTIYLA calisir.
///   • safe     : okuma/listeleme (ls, cat, grep, df, pkg search...)
///                dogrudan calisir.
///
///  Her komut kayda gecer; kullanici ne yapildigini sonradan gorebilir.
/// ════════════════════════════════════════════════════════════════════
class TermuxService {
  TermuxService._();
  static final TermuxService instance = TermuxService._();

  static const MethodChannel _ch =
      MethodChannel('skt_takip/price_check');

  /// Son çalıştırılan komutlar (en yeni sonda) — denetim izi.
  final List<({DateTime at, String cmd, bool ok, String out})> log = [];

  Future<bool> isInstalled() async {
    try {
      return await _ch.invokeMethod<bool>('termuxInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── GUVENLIK SUZGECI ───────────────────────────────────────────────

  /// Asla calistirilmayacak kaliplar.
  static final List<RegExp> _blocked = [
    RegExp(r'rm\s+(-[a-zA-Z]*\s+)*(/|/\*|\$HOME\s*$|~\s*$)'),
    RegExp(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r'),
    RegExp(r'\bmkfs\b|\bfdisk\b|\bparted\b'),
    RegExp(r'\bdd\b[^\n]*\bof=/dev/'),
    RegExp(r':\s*\(\s*\)\s*\{.*\|.*&.*\}'), // fork bombasi
    RegExp(r'\breboot\b|\bshutdown\b|\bhalt\b'),
    RegExp(r'\bchmod\s+-R\s+777\s+/'),
    RegExp(r'>\s*/dev/(sd|block)'),
    RegExp(r'\bsu\b\s|\bsu$'), // root denemesi
    RegExp(r'curl[^\n]*\|\s*(ba)?sh'), // internetten indirip dogrudan calistirma
    RegExp(r'wget[^\n]*\|\s*(ba)?sh'),
  ];

  /// Onay isteyen kaliplar (sistemi degistirir).
  static final List<RegExp> _confirm = [
    RegExp(r'\bpkg\s+(install|uninstall|upgrade)\b'),
    RegExp(r'\bapt\s+(install|remove|upgrade|purge)\b'),
    RegExp(r'\bpip\s+(install|uninstall)\b'),
    RegExp(r'\bnpm\s+(install|uninstall)\b'),
    RegExp(r'\b(rm|mv|cp)\b'),
    RegExp(r'\bchmod\b|\bchown\b'),
    RegExp(r'\bgit\s+(push|reset|clean|checkout)\b'),
    RegExp(r'\btermux-setup-storage\b'),
    RegExp(r'>\s*[^>\s]'), // dosyaya yazma (>) — uzerine yazabilir
    RegExp(r'\bkill\b|\bpkill\b'),
  ];

  /// Komutun risk sinifini belirler.
  static ShellRisk classify(String command) {
    final c = command.trim();
    if (c.isEmpty) return ShellRisk.blocked;
    for (final r in _blocked) {
      if (r.hasMatch(c)) return ShellRisk.blocked;
    }
    for (final r in _confirm) {
      if (r.hasMatch(c)) return ShellRisk.needsConfirm;
    }
    return ShellRisk.safe;
  }

  static String riskLabel(ShellRisk r) {
    switch (r) {
      case ShellRisk.safe:
        return 'Zararsız';
      case ShellRisk.needsConfirm:
        return 'Sistemi değiştirir';
      case ShellRisk.blocked:
        return 'ENGELLENDİ';
    }
  }

  // ── CALISTIRMA ─────────────────────────────────────────────────────

  /// Komutu calistirir. [allowSystemChange] false ise yalnizca [ShellRisk.safe]
  /// komutlar calisir (asistanin otomatik arac cagrilari boyle kullanir).
  Future<ShellResult> run(
    String command, {
    String? workdir,
    int timeoutMs = 30000,
    bool allowSystemChange = false,
  }) async {
    final risk = classify(command);
    if (risk == ShellRisk.blocked) {
      return const ShellResult(
        ok: false,
        error: 'Bu komut güvenlik süzgecinde engellendi '
            '(cihaza zarar verebilir).',
      );
    }
    if (risk == ShellRisk.needsConfirm && !allowSystemChange) {
      return const ShellResult(
        ok: false,
        error: 'Bu komut sistemi değiştiriyor — onay gerekiyor. '
            'Onay kartıyla çalıştırmak için shell_exec eylemini kullan.',
      );
    }

    try {
      final res = await _ch.invokeMethod<Map<Object?, Object?>>(
        'termuxRun',
        {
          'command': command,
          'workdir': workdir,
          'timeoutMs': timeoutMs,
        },
      );
      final r = ShellResult(
        ok: (res?['ok'] as bool?) ?? false,
        stdout: (res?['stdout'] as String?) ?? '',
        stderr: (res?['stderr'] as String?) ?? '',
        exitCode: (res?['exitCode'] as int?) ?? -1,
        error: res?['error'] as String?,
      );
      _remember(command, r);
      return r;
    } catch (e) {
      final r = ShellResult(ok: false, error: 'Komut çalıştırılamadı: $e');
      _remember(command, r);
      return r;
    }
  }

  void _remember(String cmd, ShellResult r) {
    log.add((
      at: DateTime.now(),
      cmd: cmd,
      ok: r.ok,
      out: r.error ?? r.stdout,
    ));
    if (log.length > 100) log.removeAt(0);
  }
}
