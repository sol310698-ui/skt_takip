import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SKT Tara ekranindaki "Hizli Akis" tercihini kalici saklar.
///
/// Hizli akis ACIK iken:
///  - "AI" butonu dogrudan foto cekmeyi acar (ara ekran yok),
///  - foto cekilip donunce otomatik Gemini'ye gonderilir,
///  - tarih okununca 2 saniyelik "dur" sansiyla otomatik kabul edilir.
/// KAPALI iken normal (adim adim, onayli) akis calisir.
///
/// Tercih cihazda saklanir; uygulama kapanip acilsa da hatirlanir.
class FlowPrefs {
  FlowPrefs._();
  static final FlowPrefs instance = FlowPrefs._();

  static const _key = 'fast_flow_enabled';
  final _storage = const FlutterSecureStorage();

  // Acilista bir kez okunup bellekte tutulur (senkron erisim icin).
  bool _fastFlow = false;
  bool _loaded = false;

  bool get fastFlow => _fastFlow;

  /// Uygulama acilisinda bir kez cagrilir; saklanan tercihi yukler.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final v = await _storage.read(key: _key);
      _fastFlow = v == 'true';
    } catch (_) {
      _fastFlow = false;
    }
    _loaded = true;
  }

  /// Tercihi degistirir ve kalici olarak yazar.
  Future<void> setFastFlow(bool value) async {
    _fastFlow = value;
    try {
      await _storage.write(key: _key, value: value ? 'true' : 'false');
    } catch (_) {
      // yazma basarisiz olsa bile bellekteki deger gecerli kalir
    }
  }
}
