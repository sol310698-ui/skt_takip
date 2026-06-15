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
}
