import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ════════════════════════════════════════════════════════════════════
///  3D DEPO HARITASI GORUNUM AYARLARI (v156)
///  Koridor boyu, isik dizilimi, duvar derinligi/egimi gibi tum sahne
///  degerleri kullanici tarafindan ayarlanabilir. Sabit sayilarla
///  tahmin yurutmek yerine kullanici kendi zevkine gore ayarlar.
/// ════════════════════════════════════════════════════════════════════
class MapViewPrefs {
  MapViewPrefs._();
  static final MapViewPrefs instance = MapViewPrefs._();
  final _storage = const FlutterSecureStorage();

  // ── Varsayilanlar ──
  /// Koridor (yol) yuksekligi — ekran yuksekliginin orani.
  double corridorPct = 0.24;

  /// Isiklarin kapladigi dikey alan orani. KORIDORDAN BAGIMSIZ:
  /// yol kisalsa bile isiklar yerinde kalir.
  double lightSpanPct = 0.70;

  /// Tavandaki armatur sayisi.
  int lightCount = 5;

  /// Duvarlarin egik ucunun hangi isiga kadar uzanacagi (1..lightCount).
  int wallDepthLight = 3;

  /// Duvar egim/daralma miktari (0 = duz dikdortgen, 1 = tam nokta).
  double wallTaper = 0.45;

  /// Duvarlarin 3D acisi (radyan).
  double wallAngle = 0.72;

  /// Isik parlakligi carpani.
  double brightness = 1.0;

  /// Tavan aydinlatmasi acik mi.
  bool lightsOn = true;

  static const _k = 'map_view_';

  Future<void> load() async {
    try {
      final all = await _storage.readAll();
      double d(String key, double def) {
        final v = all['$_k$key'];
        return v == null ? def : (double.tryParse(v) ?? def);
      }

      int i(String key, int def) {
        final v = all['$_k$key'];
        return v == null ? def : (int.tryParse(v) ?? def);
      }

      corridorPct = d('corridor', 0.24);
      lightSpanPct = d('lightSpan', 0.70);
      lightCount = i('lightCount', 5);
      wallDepthLight = i('wallDepth', 3);
      wallTaper = d('wallTaper', 0.45);
      wallAngle = d('wallAngle', 0.72);
      brightness = d('brightness', 1.0);
      lightsOn = (all['${_k}lightsOn'] ?? 'true') == 'true';
    } catch (_) {
      // Okunamazsa varsayilanlarla devam.
    }
  }

  Future<void> save() async {
    try {
      await _storage.write(key: '${_k}corridor', value: '$corridorPct');
      await _storage.write(key: '${_k}lightSpan', value: '$lightSpanPct');
      await _storage.write(key: '${_k}lightCount', value: '$lightCount');
      await _storage.write(key: '${_k}wallDepth', value: '$wallDepthLight');
      await _storage.write(key: '${_k}wallTaper', value: '$wallTaper');
      await _storage.write(key: '${_k}wallAngle', value: '$wallAngle');
      await _storage.write(key: '${_k}brightness', value: '$brightness');
      await _storage.write(key: '${_k}lightsOn', value: '$lightsOn');
    } catch (_) {}
  }

  /// Fabrika ayarlarina don.
  void reset() {
    corridorPct = 0.24;
    lightSpanPct = 0.70;
    lightCount = 5;
    wallDepthLight = 3;
    wallTaper = 0.45;
    wallAngle = 0.72;
    brightness = 1.0;
    lightsOn = true;
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  ORTAK GEOMETRI — hem painter hem duvar kirpicisi ayni sonucu
  ///  kullansin diye tek yerde hesaplanir.
  ///  [i] 0 tabanli armatur sirasi; 0 = en ustteki (en yakin/en buyuk).
  ///  Asagi indikce kuculur ve ARALARI DARALIR (t'nin artisi yavaslar).
  /// ══════════════════════════════════════════════════════════════════
  static double lightT(int i, int count) {
    final u = (i + 0.35) / count;
    return 1 - (1 - u) * (1 - u);
  }

  /// [i]. armaturun ekrandaki dikey konumu.
  static double lightY(int i, int count, double span, {double topPad = 10}) {
    return topPad + (span - topPad) * lightT(i, count);
  }
}
