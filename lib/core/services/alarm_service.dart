import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// ════════════════════════════════════════════════════════════════════
///  Alarm servisi — "alarm" paketi sarmalayicisi.
///  Native taraf kilit ekrani, ses, titresim, tam ekran intent'i yonetir.
/// ════════════════════════════════════════════════════════════════════
class AlarmService {
  AlarmService._();

  /// Uygulama acilisinda cagrilir.
  static Future<void> init() async {
    await Alarm.init();
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
  }) async {
    final settings = AlarmSettings(
      id: id,
      dateTime: when,
      // alarm.mp3 eklendiyse onu, yoksa mevcut beep sesini kullan.
      assetAudioPath: 'assets/sounds/beep_product.wav',
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: false,
      androidFullScreenIntent: true, // kilit ekraninda tam ekran
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
