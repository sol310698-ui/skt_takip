import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// ════════════════════════════════════════════════════════════════════
///  Alarm servisi — "alarm" paketi sarmalayicisi.
///  Native taraf kilit ekrani, ses, titresim, tam ekran intent'i yonetir.
/// ════════════════════════════════════════════════════════════════════
class AlarmService {
  AlarmService._();

  static const _fsChannel = MethodChannel('skt_takip/fullscreen');

  /// Uygulama acilisinda cagrilir.
  static Future<void> init() async {
    await Alarm.init();
  }

  /// Android 14+ tam ekran intent izni var mi? (Kilit ekrani alarmi icin sart.)
  static Future<bool> canUseFullScreenIntent() async {
    try {
      final r = await _fsChannel.invokeMethod<bool>('canUseFullScreenIntent');
      return r ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Tam ekran intent izni ayar sayfasini ac (Android 14+).
  static Future<void> openFullScreenIntentSettings() async {
    try {
      await _fsChannel.invokeMethod('openFullScreenIntentSettings');
    } catch (_) {}
  }

  /// Gerekli izinleri ister: bildirim + tam zamanli alarm.
  /// Alarmin kilit ekraninda tam ekran acilmasi icin sart.
  static Future<void> requestPermissions() async {
    // Bildirim izni (Android 13+).
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    // Tam zamanli alarm izni (Android 12+).
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
    // Pil optimizasyonundan muafiyet — telefon uykudayken alarmin
    // susturulmamasi icin KRITIK.
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// Pil optimizasyonu muafiyeti verilmis mi?
  static Future<bool> isBatteryOptimizationDisabled() async {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// Pil optimizasyonu muafiyeti iste (ayar ekranini acar).
  static Future<void> requestDisableBatteryOptimization() async {
    await Permission.ignoreBatteryOptimizations.request();
  }

  /// Tam zamanli alarm izni verilmis mi?
  static Future<bool> hasExactAlarmPermission() async {
    return await Permission.scheduleExactAlarm.isGranted;
  }

  /// Belirli bir tarihte alarm kur.
  static Future<void> setAlarmAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? audioPath, // null -> cihaz varsayilan ALARM sesi; aksi halde dosya/asset yolu
  }) async {
    final settings = AlarmSettings(
      id: id,
      dateTime: when,
      // audioPath verilmisse onu (telefondaki muzik dosyasi), yoksa
      // paketle gelen alarm.mp3; o da yoksa paket cihaz alarm sesine doner.
      assetAudioPath: audioPath ?? 'assets/sounds/alarm.mp3',
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: false,
      androidFullScreenIntent: true, // kilit ekraninda tam ekran
      // Alarm STREAM_ALARM'da calar (medya degil). volumeEnforced ile
      // ses kisik/sessiz olsa bile alarm seviyesi garanti edilir.
      volumeSettings: VolumeSettings.fade(
        volume: 0.9,
        fadeDuration: const Duration(seconds: 3),
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: title,
        body: body,
        stopButton: 'Durdur',
        icon: 'ic_launcher',
        iconColor: const Color(0xFF5B6CF0),
      ),
    );
    await Alarm.set(alarmSettings: settings);
  }

  /// Alarmi durdur/iptal et.
  static Future<void> stop(int id) async {
    await Alarm.stop(id);
  }

  /// Tum alarmlari durdur.
  static Future<void> stopAll() async {
    await Alarm.stopAll();
  }
}
