import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Internet barkod sorgularinin hangi acik veri tabani kaynaklarini
/// kullanacagini belirler.
///
///  - Open Food Facts (OFF): gida/market urunleri
///  - Open Beauty Facts (OBF): kozmetik/kisisel bakim urunleri
///
/// Her ikisi de ACIK olabilir (sorgular sirayla denenir, ilk bulunan
/// kullanilir), sadece biri acik olabilir, ya da ikisi de kapali olabilir
/// (bu durumda internet sorgusu yapilmaz). Tercih cihazda kalici saklanir.
///
/// Tum barkod sorgulari BarcodeLookupService uzerinden gectigi icin, bu
/// tercih TEK merkezden tum uygulamayi etkiler.
class DbSourcePrefs {
  DbSourcePrefs._();
  static final DbSourcePrefs instance = DbSourcePrefs._();

  static const _keyOff = 'db_source_off_enabled';
  static const _keyObf = 'db_source_obf_enabled';

  final _storage = const FlutterSecureStorage();

  // Acilista bir kez okunup bellekte tutulur (senkron erisim icin).
  bool _offEnabled = true; // varsayilan: OFF acik (gida — mevcut davranis)
  bool _obfEnabled = false; // varsayilan: OBF kapali
  bool _loaded = false;

  bool get offEnabled => _offEnabled;
  bool get obfEnabled => _obfEnabled;

  /// En az bir kaynak acik mi? (Hicbiri acik degilse internet sorgusu
  /// atlanir.)
  bool get anyEnabled => _offEnabled || _obfEnabled;

  /// Uygulama acilisinda bir kez cagrilir; saklanan tercihleri yukler.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final off = await _storage.read(key: _keyOff);
      final obf = await _storage.read(key: _keyObf);
      // Daha once hic kaydedilmemisse varsayilanlari koru.
      if (off != null) _offEnabled = off == 'true';
      if (obf != null) _obfEnabled = obf == 'true';
    } catch (_) {
      // okuma hatasinda varsayilanlar gecerli kalir
    }
    _loaded = true;
  }

  Future<void> setOff(bool value) async {
    _offEnabled = value;
    try {
      await _storage.write(key: _keyOff, value: value ? 'true' : 'false');
    } catch (_) {}
  }

  Future<void> setObf(bool value) async {
    _obfEnabled = value;
    try {
      await _storage.write(key: _keyObf, value: value ? 'true' : 'false');
    } catch (_) {}
  }
}
