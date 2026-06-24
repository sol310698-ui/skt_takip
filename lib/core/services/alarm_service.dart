import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_logger.dart';
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

    // Tum izin durumlarini logla (alarm calmazsa hangisinin eksik oldugunu
    // gormek icin).
    final notif = await Permission.notification.isGranted;
    final exact = await Permission.scheduleExactAlarm.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    await AppLogger.instance.log('IZIN',
        'bildirim=$notif tamZamanliAlarm=$exact '
        'pilMuafiyeti=$battery tamEkranIntent=$canFsi');
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

  /// Varsayilan (paketle gelen) guvenilir alarm sesi.
  static const String _defaultAsset = 'assets/sounds/alarm.mp3';

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
    final candidate = audioPath ?? globalSound;

    // ── SES YOLUNU GUVENLI SECON ──
    // Kullanicinin sectigi ses bir DOSYA yolu (orn /data/.../snd_x.wav).
    // ONEMLI BULGU: "alarm" paketi Android'de DOSYA yolundan .wav/.ogg gibi
    // formatlari guvenilir CALAMIYOR; alarm kuruluyor, foreground service
    // basliyor (RINGING event geliyor) ama ses CIKMIYOR ve full-screen intent
    // tetiklenmiyor -> ne ses ne ekran. (Gercek cihaz logu ile dogrulandi.)
    // Bu yuzden: yalnizca .mp3 dosya yollarina izin veriyoruz; diger
    // formatlar VEYA dosya yoksa, paketle gelen guvenilir asset'e (alarm.mp3)
    // duseruz. Asset yollari ('assets/...') oldugu gibi gecer.
    String effective;
    String reason;
    if (candidate == null || candidate.trim().isEmpty) {
      effective = _defaultAsset;
      reason = 'ayarda ses yok -> varsayilan asset';
    } else if (candidate.startsWith('assets/')) {
      effective = candidate;
      reason = 'asset yolu';
    } else {
      final lower = candidate.toLowerCase();
      final isMp3 = lower.endsWith('.mp3');
      bool exists = false;
      try {
        exists = File(candidate).existsSync();
      } catch (_) {}

      if (!exists) {
        effective = _defaultAsset;
        reason = 'dosya bulunamadi -> varsayilan asset';
      } else if (!isMp3) {
        // .wav/.ogg/.m4a vb: guvenilmez -> guvenilir asset'e dus.
        effective = _defaultAsset;
        reason = 'desteklenmeyen format (${lower.split('.').last}) '
            '-> varsayilan asset (mp3)';
      } else {
        effective = candidate;
        reason = 'gecerli mp3 dosya yolu';
      }
    }
    await AppLogger.instance
        .log('ALARM', 'Ses secimi: $reason -> $effective');

    final settings = AlarmSettings(
      id: id,
      dateTime: when,
      assetAudioPath: effective,
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: true, // uygulama oldurulurse kullaniciyi uyar
      androidFullScreenIntent: true, // kilit ekraninda tam ekran
      // KRITIK: Bildirime tiklayinca / uygulama task'i degisince alarm
      // DURMASIN. Boylece bildirimden uygulamaya gecince ses devam eder,
      // alarm ekrani acilir ve kullanici "Durdur"a basana kadar calar.
      androidStopAlarmOnTermination: false,
      // Alarm STREAM_ALARM'da calar. Baslangic 0.8, 5 sn'de yukselir (fade).
      // volumeEnforced: TRUE — KRITIK. Telefonun alarm ses seviyesi kisik veya
      // 0 olsa bile, alarm caldigi surece sistemin alarm sesini bu seviyeye
      // ZORLAR ve kullanici dusurmeye calissa da geri yukseltir. Bu olmadan,
      // alarm sesi kisikken alarm sessiz calabiliyordu (yasanan sorun).
      volumeSettings: VolumeSettings.fade(
        volume: 0.8,
        fadeDuration: const Duration(seconds: 5),
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: title,
        body: body,
        stopButton: 'Durdur',
        icon: 'ic_launcher',
        iconColor: const Color(0xFF2563EB),
      ),
    );
    await Alarm.set(alarmSettings: settings);
    await AppLogger.instance.log('ALARM',
        'KURULDU id=$id zaman=${when.toIso8601String()} '
        'ses=$effective baslik="$title" '
        '(simdi=${DateTime.now().toIso8601String()})');
  }

  /// Alarmi durdur/iptal et.
  static Future<void> stop(int id) async {
    await AppLogger.instance.log('ALARM', 'DURDURULDU id=$id (kullanici).');
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

  /// Su an ZAMANLANMIS (kurulu) tum alarm ID'lerini dondurur.
  /// refreshAllAlarms'in zaten kurulu alarmlari gereksiz yere silip yeniden
  /// kurmamasi icin kullanilir (bu yeniden kurulum haftalik alarmlari
  /// bozabiliyordu; mesai cikis alarmi bir kez kurulup dokunulmadigi icin
  /// kusursuz calisiyor — ayni davranisi haftaliga da uyguluyoruz).
  static Future<Set<int>> scheduledAlarmIds() async {
    try {
      final alarms = await Alarm.getAlarms();
      return alarms.map((a) => a.id).toSet();
    } catch (_) {
      return <int>{};
    }
  }

  /// Kurulu alarmlarin id -> tetik zamani haritasi.
  /// refreshAllAlarms, "kurulu ama zamani gecmis/drift etmis" alarmlari
  /// ayirt edip yeniden kurabilmek icin kullanir.
  static Future<Map<int, DateTime>> scheduledAlarmsMap() async {
    try {
      final alarms = await Alarm.getAlarms();
      return {for (final a in alarms) a.id: a.dateTime};
    } catch (_) {
      return <int, DateTime>{};
    }
  }
}
