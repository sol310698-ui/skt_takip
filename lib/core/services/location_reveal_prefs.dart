import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reyondaki ürün konumu bulununca oynayan "kamera inişi" canlandırması
/// (showLocationFlythrough / _playLocationReveal, bkz. label_inspect_screen
/// ve location_reveal.dart) için açık/kapalı tercihini kalıcı saklar.
///
/// Kapatıldığında ne otomatik oynatma ne de karta dokununca tekrar
/// oynatma çalışır — konum bilgisi yine de düz metin olarak gösterilir,
/// sadece canlandırma atlanır.
class LocationRevealPrefs extends ChangeNotifier {
  LocationRevealPrefs._();
  static final LocationRevealPrefs instance = LocationRevealPrefs._();

  static const _key = 'reyon_location_reveal_enabled';
  final _storage = const FlutterSecureStorage();

  // Varsayilan: acik.
  bool _enabled = true;
  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      _enabled = v == null ? true : v == 'true';
    } catch (_) {
      _enabled = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      await _storage.write(key: _key, value: value ? 'true' : 'false');
    } catch (_) {}
  }
}
