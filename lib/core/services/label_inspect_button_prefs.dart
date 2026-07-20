import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// "Etiket İncele" butonu (artık uygulamanın TÜM sayfalarında görünen,
/// bağımsız/global FAB) için tercihleri kalıcı saklar:
///  - nabız animasyonunun açık/kapalı olması
///  - kullanıcının uzun basıp SÜRÜKLEYEREK taşıdığı özel konumu
///
/// ChangeNotifier olduğu için buton widget'ı AnimatedBuilder ile bunu
/// dinleyip anında tepki verir (ayarlar ekranından değiştirilince o an
/// bulunulan ekranda bile güncellenir).
class LabelInspectButtonPrefs extends ChangeNotifier {
  LabelInspectButtonPrefs._();
  static final LabelInspectButtonPrefs instance = LabelInspectButtonPrefs._();

  static const _key = 'label_inspect_fab_animation_enabled';
  static const _keyPosX = 'label_inspect_fab_pos_fx';
  static const _keyPosY = 'label_inspect_fab_pos_fy';
  final _storage = const FlutterSecureStorage();

  // Varsayilan: acik (dikkat cekmesi icin).
  bool _animationEnabled = true;
  bool get animationEnabled => _animationEnabled;

  // Kullanicinin uzun-basip surukleyerek tasidigi ozel konum (ekran
  // genisligi/yuksekligine oranli, 0..1). null = ozel konum yok, varsayilan
  // (sag alt, + butonunun ustu) kullanilir.
  double? _posFx;
  double? _posFy;
  double? get posFx => _posFx;
  double? get posFy => _posFy;
  bool get hasCustomPosition => _posFx != null && _posFy != null;

  /// Uygulama açılışında bir kez çağrılır; saklanan tercihi yükler.
  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      _animationEnabled = v == null ? true : v == 'true';
    } catch (_) {
      _animationEnabled = true;
    }
    try {
      final fx = await _storage.read(key: _keyPosX);
      final fy = await _storage.read(key: _keyPosY);
      _posFx = fx != null ? double.tryParse(fx) : null;
      _posFy = fy != null ? double.tryParse(fy) : null;
    } catch (_) {
      _posFx = null;
      _posFy = null;
    }
  }

  Future<void> setAnimationEnabled(bool value) async {
    _animationEnabled = value;
    notifyListeners();
    try {
      await _storage.write(
          key: _key, value: value ? 'true' : 'false');
    } catch (_) {}
  }

  /// Butonun yeni ozel konumunu kaydeder (0..1 arasi oranli koordinatlar,
  /// farkli ekran boyutlarina uyum saglasin diye).
  Future<void> setPosition(double fx, double fy) async {
    _posFx = fx.clamp(0.0, 1.0);
    _posFy = fy.clamp(0.0, 1.0);
    notifyListeners();
    try {
      await _storage.write(key: _keyPosX, value: _posFx.toString());
      await _storage.write(key: _keyPosY, value: _posFy.toString());
    } catch (_) {}
  }

  /// Butonu varsayilan konumuna (sag alt, + butonunun ustu) geri dondurur.
  Future<void> resetPosition() async {
    _posFx = null;
    _posFy = null;
    notifyListeners();
    try {
      await _storage.delete(key: _keyPosX);
      await _storage.delete(key: _keyPosY);
    } catch (_) {}
  }
}
