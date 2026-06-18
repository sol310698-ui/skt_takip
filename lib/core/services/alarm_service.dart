import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'skt_alarm_settings.dart';

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

  /// Kalici on plan servisini baslat (uygulamayi swipe-kill'e karsi tutar).
  static Future<void> startKeepAlive() async {
    try {
      await _fsChannel.invokeMethod('startKeepAlive');
    } catch (_) {}
  }

  /// Kalici on plan servisini durdur.
  static Future<void> stopKeepAlive() async {
    try {
      await _fsChannel.invokeMethod('stopKeepAlive');
    } catch (_) {}
  }

  /// Alarm sesini (STREAM_ALARM) maksimuma cikar (1 dk kapatilmadiysa).
  static Future<void> raiseAlarmVolume() async {
    try {
      await _fsChannel.invokeMethod('raiseAlarmVolume');
    } catch (_) {}
  }

  /// Gerekli izinleri ister: bildirim + tam zamanli alarm + tam ekran intent.
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
    // KRITIK (Android 14+): Tam ekran intent izni reddedildiyse, sistem
    // alarmi sessizce normal bildirime dusurur ve kilit ekraninda ACILMAZ.
    // Izin yoksa kullaniciyi ayar sayfasina yonlendir.
    final canFsi = await canUseFullScreenIntent();
    if (!canFsi) {
      await openFullScreenIntentSettings();
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
  /// audioPath verilmezse, kullanicinin sectigi GENEL alarm sesi kullanilir.
  static Future<void> setAlarmAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    String? audioPath, // null -> genel ayardaki ses (o da yoksa varsayilan)
  }) async {
    // Genel alarm sesini ayardan oku (tum alarmlar ayni sesi kullanir).
    final globalSound = await SktAlarmSettings.instance.getSoundPath();
    final effectivePath = audioPath ?? globalSound;
    final settings = AlarmSettings(
      id: id,
      dateTime: when,
      // Once parametre, sonra genel ayar sesi, o da yoksa paketle gelen
      // alarm.mp3 (o da yoksa paket cihaz alarm sesine doner).
      assetAudioPath: effectivePath ?? 'assets/sounds/alarm.mp3',
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: true, // uygulama oldurulurse kullaniciyi uyar
      androidFullScreenIntent: true, // kilit ekraninda tam ekran
      // KRITIK: Bildirime tiklayinca / uygulama task'i degisince alarm
      // DURMASIN. Boylece bildirimden uygulamaya gecince ses devam eder,
      // alarm ekrani acilir ve kullanici "Durdur"a basana kadar calar.
      androidStopAlarmOnTermination: false,
      // Alarm STREAM_ALARM'da calar. volumeEnforced VERILMIYOR: sistem sesi
      // zorla en uste cikarmaz, kullanici onceden ayarladigi/ses tusuyla
      // degistirebilir. Baslangic 0.7 (makul), kademeli yukselir (fade).
      // 1 dakika kapatilmazsa AlarmRingScreen sesi ayrica artirir.
      volumeSettings: VolumeSettings.fade(
        volume: 0.7,
        fadeDuration: const Duration(seconds: 5),
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
    // Kullanici alarmi durdurdu -> CPU/ekran kilidini birak (pil tasarrufu).
    // (getAlarms zamanlanmis alarmlari da sayar; burada calan alarm
    //  durduruldugu icin kosulsuz birakmak dogru.)
    await WakelockPlus.disable();
  }

  /// Tum alarmlari durdur.
  static Future<void> stopAll() async {
    await Alarm.stopAll();
    await WakelockPlus.disable();
  }
}
