import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Uygulamanin tema modu tercihini (Sistem / Aydinlik / Koyu) kalici saklar
/// ve degisince dinleyicileri (MaterialApp) haberdar eder.
class ThemePrefs extends ChangeNotifier {
  ThemePrefs._();
  static final ThemePrefs instance = ThemePrefs._();

  static const _key = 'theme_mode';
  static const _colorKey = 'theme_primary_color';
  static const _accentKey = 'theme_accent_id';
  static const _compactKey = 'theme_compact';
  static const _daylightKey = 'theme_daylight_auto';
  final _storage = const FlutterSecureStorage();

  // Kullanicinin sectigi ANA RENK (primary). Varsayilan: canli mavi.
  // Uygulamadaki butonlar, vurgular, secili durumlar bu renge gore degisir.
  int _primaryColor = 0xFF2563EB;
  int get primaryColor => _primaryColor;
  Color get primaryColorValue => Color(_primaryColor);

  // ── VURGU PALETI (#10) ──────────────────────────────────────────────
  // AppTheme.accentPalettes icindeki bir paletin id'si ('green' varsayilan).
  String _accentId = 'green';
  String get accentId => _accentId;

  // ── LISTE YOGUNLUGU (#10) ──────────────────────────────────────────
  // false = Ferah (standart), true = Kompakt.
  bool _compact = false;
  bool get compact => _compact;

  // ── GUN ISIGI OTOMATIK TEMA (#1) ───────────────────────────────────
  // Acikken tema modu SAATE gore secilir: gunduz aydinlik, gece koyu.
  bool _daylightAuto = false;
  bool get daylightAuto => _daylightAuto;

  /// Gun isigi otomatik moda gore o an aydinlik mi olmali? (07:00–19:00 arasi
  /// gunduz = aydinlik; disi gece = koyu.) daylightAuto kapaliyken cagrilmaz.
  bool get isDaytimeNow {
    final h = DateTime.now().hour;
    return h >= 7 && h < 19;
  }

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
    // Vurgu paleti + yogunluk + gun isigi tercihleri.
    try {
      final a = await _storage.read(key: _accentKey);
      if (a != null && a.isNotEmpty) _accentId = a;
    } catch (_) {}
    try {
      _compact = (await _storage.read(key: _compactKey)) == '1';
    } catch (_) {}
    try {
      _daylightAuto = (await _storage.read(key: _daylightKey)) == '1';
    } catch (_) {}
  }

  /// Vurgu paletini sec (AppTheme.accentPalettes id'si) ve dinleyicileri
  /// guncelle (MaterialApp yeni renkle yeniden kurulur).
  Future<void> setAccentId(String id) async {
    _accentId = id;
    notifyListeners();
    try {
      await _storage.write(key: _accentKey, value: id);
    } catch (_) {}
  }

  /// Liste yogunlugunu ayarla (true = kompakt).
  Future<void> setCompact(bool value) async {
    _compact = value;
    notifyListeners();
    try {
      await _storage.write(key: _compactKey, value: value ? '1' : '0');
    } catch (_) {}
  }

  /// Gun isigi otomatik temayi ac/kapat.
  Future<void> setDaylightAuto(bool value) async {
    _daylightAuto = value;
    notifyListeners();
    try {
      await _storage.write(key: _daylightKey, value: value ? '1' : '0');
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
