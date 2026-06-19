import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SKT imha alarmi ayarlari (acik/kapali + saat).
/// flutter_secure_storage ile saklanir (ekstra paket gerekmez).
class SktAlarmSettings {
  SktAlarmSettings._();
  static final SktAlarmSettings instance = SktAlarmSettings._();

  static const _storage = FlutterSecureStorage();
  static const _kEnabled = 'skt_alarm_enabled';
  static const _kHour = 'skt_alarm_hour';
  static const _kMinute = 'skt_alarm_minute';
  // Tum alarmlarin kullandigi TEK genel alarm sesi (yol + gosterim adi).
  static const _kSoundPath = 'alarm_sound_path';
  static const _kSoundName = 'alarm_sound_name';

  Future<bool> isEnabled() async {
    final v = await _storage.read(key: _kEnabled);
    return v == 'true';
  }

  Future<void> setEnabled(bool value) =>
      _storage.write(key: _kEnabled, value: value ? 'true' : 'false');

  Future<int> getHour() async {
    final v = await _storage.read(key: _kHour);
    return int.tryParse(v ?? '') ?? 19; // varsayilan 19:00
  }

  Future<int> getMinute() async {
    final v = await _storage.read(key: _kMinute);
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> setTime(int hour, int minute) async {
    await _storage.write(key: _kHour, value: '$hour');
    await _storage.write(key: _kMinute, value: '$minute');
  }

  // ── Genel alarm sesi (tum alarmlar icin TEK ses) ──
  /// Secili alarm sesi dosya yolu (null = paket varsayilani).
  Future<String?> getSoundPath() => _storage.read(key: _kSoundPath);

  /// Secili alarm sesi gosterim adi (null = "Varsayilan").
  Future<String?> getSoundName() => _storage.read(key: _kSoundName);

  Future<void> setSound(String path, String name) async {
    await _storage.write(key: _kSoundPath, value: path);
    await _storage.write(key: _kSoundName, value: name);
  }

  /// Varsayilana don (secili sesi temizle).
  Future<void> clearSound() async {
    await _storage.delete(key: _kSoundPath);
    await _storage.delete(key: _kSoundName);
  }

  /// Kayitli genel ses guvenilir degilse (mp3 disi format, orn .wav/.ogg)
  /// otomatik temizler. "alarm" paketi dosya yolundan bu formatlari guvenilir
  /// calamadigi icin alarm sessiz kalip ekran acilmiyordu. Uygulama acilisinda
  /// bir kez cagrilir; sorunlu ayari varsayilan (paket asset mp3) sesine ceker.
  Future<bool> sanitizeSoundIfNeeded() async {
    final path = await _storage.read(key: _kSoundPath);
    if (path == null || path.trim().isEmpty) return false;
    final lower = path.toLowerCase();
    if (lower.startsWith('assets/')) return false; // asset zaten guvenli
    if (lower.endsWith('.mp3')) return false; // mp3 dosya yolu kabul
    // Diger her sey (.wav/.ogg/.m4a vb) -> temizle.
    await clearSound();
    return true;
  }

  // ── Kalici servis (swipe-kill korumasi) tercihi ──
  static const _kKeepAlive = 'alarm_keepalive';

  /// Kalici on plan servisi acik mi? (Varsayilan: kapali.)
  Future<bool> isKeepAliveOn() async {
    final v = await _storage.read(key: _kKeepAlive);
    return v == 'true';
  }

  Future<void> setKeepAlive(bool value) =>
      _storage.write(key: _kKeepAlive, value: value ? 'true' : 'false');

  // ── QR ile alarm kapatma kilidi ──
  static const _kQrEnabled = 'alarm_qr_enabled';
  static const _kQrValue = 'alarm_qr_value';

  /// QR kilidi acik mi? (Alarm kapatmak icin QR taranmali.)
  Future<bool> isQrLockOn() async {
    final v = await _storage.read(key: _kQrEnabled);
    return v == 'true';
  }

  Future<void> setQrLock(bool value) =>
      _storage.write(key: _kQrEnabled, value: value ? 'true' : 'false');

  /// Tanimli QR degeri (alarm kapatma icin eslesmesi gereken metin).
  Future<String?> getQrValue() => _storage.read(key: _kQrValue);

  Future<void> setQrValue(String value) =>
      _storage.write(key: _kQrValue, value: value);

  Future<void> clearQrValue() => _storage.delete(key: _kQrValue);
}
