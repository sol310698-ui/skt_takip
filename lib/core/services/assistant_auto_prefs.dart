import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ════════════════════════════════════════════════════════════════════
///  ASISTAN OTOMATIK MOD TERCIHI
/// ────────────────────────────────────────────────────────────────────
///  Acikken (AKILLI OTOMATIK) asistanin urettigi ZARARSIZ eylemler onay
///  beklemeden calisir; kullanici "yap" der, asistan araya girmeden yapar.
///
///  GUVENLIK: Geri donusu olmayan / riskli eylemler (silme, PIN degistirme,
///  ham SQL, shell komutu, kilidi kapatma) bu mod ACIK olsa bile YINE onay
///  kartiyla sorulur — bkz. AssistantAction.isDestructive. Boylece hiz
///  kazanilir ama yanlis bir silme/SQL sorulmadan uygulanmaz.
/// ════════════════════════════════════════════════════════════════════
class AssistantAutoPrefs extends ChangeNotifier {
  AssistantAutoPrefs._();
  static final AssistantAutoPrefs instance = AssistantAutoPrefs._();

  static const _key = 'assistant_auto_mode';
  final _storage = const FlutterSecureStorage();

  // Varsayilan: ACIK (kullanici otomatik akis istedi). Riskli eylemler
  // zaten ayrica onay ister, bu yuzden acik varsayilan guvenlidir.
  bool _auto = true;
  bool get auto => _auto;

  Future<void> load() async {
    try {
      final v = await _storage.read(key: _key);
      if (v != null) _auto = v == '1';
    } catch (_) {
      // Okuma hatasinda varsayilanda kal.
    }
  }

  Future<void> setAuto(bool value) async {
    if (_auto == value) return;
    _auto = value;
    notifyListeners();
    try {
      await _storage.write(key: _key, value: value ? '1' : '0');
    } catch (_) {}
  }

  Future<void> toggle() => setAuto(!_auto);
}
