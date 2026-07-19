import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// "Etiket İncele" butonu (ana ekranda sol altta, bağımsız FAB) için
/// animasyon tercihini kalıcı saklar.
///
/// Buton her zaman gösterilir; burada sadece dikkat çekici nabız
/// animasyonunun açık/kapalı olması yönetilir. ChangeNotifier olduğu
/// için buton widget'ı AnimatedBuilder ile bunu dinleyip anında tepki
/// verir (ayarlar ekranından değiştirilince ana ekrana dönmeden bile
/// güncellenir).
class LabelInspectButtonPrefs extends ChangeNotifier {
  LabelInspectButtonPrefs._();
  static final LabelInspectButtonPrefs instance = LabelInspectButtonPrefs._();

  static const _key = 'label_inspect_fab_animation_enabled';
  final _storage = const FlutterSecureStorage();

  // Varsayilan: acik (dikkat cekmesi icin).
  bool _animationEnabled = true;
  bool get animationEnabled => _animationEnabled;

  /// Uygulama açılışında bir kez çağrılır; saklanan tercihi yükler.
  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      _animationEnabled = v == null ? true : v == 'true';
    } catch (_) {
      _animationEnabled = true;
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
}
