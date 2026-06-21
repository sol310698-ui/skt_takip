import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Uygulamanin tema modu tercihini (Sistem / Aydinlik / Koyu) kalici saklar
/// ve degisince dinleyicileri (MaterialApp) haberdar eder.
class ThemePrefs extends ChangeNotifier {
  ThemePrefs._();
  static final ThemePrefs instance = ThemePrefs._();

  static const _key = 'theme_mode';
  final _storage = const FlutterSecureStorage();

  ThemeMode _mode = ThemeMode.dark; // varsayilan: koyu
  ThemeMode get mode => _mode;

  /// Acilista bir kez cagrilir; saklanan tercihi yukler.
  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      _mode = switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    } catch (_) {
      _mode = ThemeMode.dark;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    try {
      final s = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await _storage.write(key: _key, value: s);
    } catch (_) {}
  }
}
