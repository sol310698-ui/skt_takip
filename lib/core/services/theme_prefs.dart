import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Uygulamanin tema modu tercihini (Sistem / Aydinlik / Koyu) kalici saklar
/// ve degisince dinleyicileri (MaterialApp) haberdar eder.
class ThemePrefs extends ChangeNotifier {
  ThemePrefs._();
  static final ThemePrefs instance = ThemePrefs._();

  static const _key = 'theme_mode';
  static const _colorKey = 'theme_primary_color';
  final _storage = const FlutterSecureStorage();

  // Kullanicinin sectigi ANA RENK (primary). Varsayilan: canli mavi.
  // Uygulamadaki butonlar, vurgular, secili durumlar bu renge gore degisir.
  int _primaryColor = 0xFF2563EB;
  int get primaryColor => _primaryColor;
  Color get primaryColorValue => Color(_primaryColor);

  // Soft Glass tasarimi acik temada en iyi gorundugu icin varsayilan
  // ACIK yapildi (eskiden koyuydu). Kullanici dilerse Ayarlar'dan
  // Koyu/Sistem secebilir; bu sadece ILK kurulumdaki varsayilan.
  ThemeMode _mode = ThemeMode.light; // varsayilan: acik (Soft Glass)
  ThemeMode get mode => _mode;

  /// Acilista bir kez cagrilir; saklanan tercihi yukler.
  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      _mode = switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    } catch (_) {
      _mode = ThemeMode.light;
    }
    // Ana renk tercihini yukle.
    try {
      final c = await _storage.read(key: _colorKey);
      if (c != null) {
        final parsed = int.tryParse(c);
        if (parsed != null) _primaryColor = parsed;
      }
    } catch (_) {}
  }

  /// Kullanicinin sectigi ana rengi kaydet ve dinleyicileri guncelle.
  Future<void> setPrimaryColor(int colorValue) async {
    _primaryColor = colorValue;
    notifyListeners();
    try {
      await _storage.write(key: _colorKey, value: colorValue.toString());
    } catch (_) {}
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
