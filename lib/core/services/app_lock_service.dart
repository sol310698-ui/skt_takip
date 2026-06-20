import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// ════════════════════════════════════════════════════════════════════
///  Uygulama kilidi: PIN (birincil) + biyometri (parmak izi/yuz, ek/hizli
///  secenek) + is yeri konumuna gore otomatik bilgi notu.
///
///  PIN duz metin DEGIL, SHA-256 hash olarak saklanir (flutter_secure_
///  storage zaten sifreli, ama ekstra guvenlik katmani icin hash'liyoruz).
///  Is yeri konumu (lat/lng) ve PIN, ayni guvenli depoda saklanir.
/// ════════════════════════════════════════════════════════════════════
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _storage = FlutterSecureStorage();
  static const _kPinHash = 'app_lock_pin_hash';
  static const _kBiometricEnabled = 'app_lock_biometric_enabled';
  static const _kWorkLat = 'app_lock_work_lat';
  static const _kWorkLng = 'app_lock_work_lng';
  static const _kWorkRadius = 'app_lock_work_radius_m';
  static const _kLockEnabled = 'app_lock_enabled';

  final LocalAuthentication _auth = LocalAuthentication();

  // ─────────────────────────── PIN ───────────────────────────

  String _hash(String pin) => sha256.convert(utf8.encode(pin)).toString();

  /// PIN belirlenmis mi? (Ilk kurulumda kullanici PIN belirlemeye zorlanir.)
  Future<bool> hasPin() async {
    final v = await _storage.read(key: _kPinHash);
    return v != null && v.isNotEmpty;
  }

  /// PIN belirle/degistir (4-6 haneli rakam onerilir, kisitlama yok).
  Future<void> setPin(String pin) async {
    await _storage.write(key: _kPinHash, value: _hash(pin));
  }

  /// Girilen PIN dogru mu?
  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kPinHash);
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  /// PIN'i kaldir (kilit tamamen kapatilirken kullanilir).
  Future<void> clearPin() async {
    await _storage.delete(key: _kPinHash);
  }

  // ─────────────────────────── Kilit acik/kapali ───────────────────────────

  /// Kilit ozelligi acik mi? (PIN varsa varsayilan acik kabul edilir.)
  Future<bool> isLockEnabled() async {
    final v = await _storage.read(key: _kLockEnabled);
    if (v == null) return await hasPin(); // PIN varsa varsayilan acik
    return v == '1';
  }

  Future<void> setLockEnabled(bool enabled) async {
    await _storage.write(key: _kLockEnabled, value: enabled ? '1' : '0');
  }

  // ─────────────────────────── Biyometri ───────────────────────────

  /// Cihaz biyometri DESTEKLIYOR mu (donanim + kayitli parmak izi/yuz var mi)?
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck && !isSupported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Kullanici ayarlardan biyometriyi ACTI mi?
  Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _kBiometricEnabled);
    return v == '1';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
        key: _kBiometricEnabled, value: enabled ? '1' : '0');
  }

  /// Biyometri dogrulamasini tetikler. Basarili -> true.
  /// Kullanici vazgecerse veya hata olursa -> false (PIN'e dusulur).
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Uygulamayı açmak için kimliğinizi doğrulayın',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────── Is yeri konumu ───────────────────────────

  /// Is yeri konumu tanimli mi?
  Future<bool> hasWorkLocation() async {
    final lat = await _storage.read(key: _kWorkLat);
    return lat != null;
  }

  /// Is yeri konumunu kaydet (haritadan secilen nokta).
  Future<void> setWorkLocation(double lat, double lng,
      {double radiusMeters = 150}) async {
    await _storage.write(key: _kWorkLat, value: lat.toString());
    await _storage.write(key: _kWorkLng, value: lng.toString());
    await _storage.write(
        key: _kWorkRadius, value: radiusMeters.toString());
  }

  Future<void> clearWorkLocation() async {
    await _storage.delete(key: _kWorkLat);
    await _storage.delete(key: _kWorkLng);
    await _storage.delete(key: _kWorkRadius);
  }

  /// Kayitli is yeri konumunu doner (yoksa null).
  Future<({double lat, double lng, double radius})?> getWorkLocation() async {
    final latStr = await _storage.read(key: _kWorkLat);
    final lngStr = await _storage.read(key: _kWorkLng);
    final radiusStr = await _storage.read(key: _kWorkRadius);
    if (latStr == null || lngStr == null) return null;
    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    final radius = double.tryParse(radiusStr ?? '150') ?? 150;
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng, radius: radius);
  }

  /// Verilen konum, kayitli is yeri konumuna yariçap icinde mi?
  /// Haversine formulu ile metre cinsinden mesafe hesaplanir.
  Future<bool> isWithinWorkLocation(double lat, double lng) async {
    final work = await getWorkLocation();
    if (work == null) return false;
    final distance = _distanceMeters(lat, lng, work.lat, work.lng);
    return distance <= work.radius;
  }

  double _distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // metre
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);
}
