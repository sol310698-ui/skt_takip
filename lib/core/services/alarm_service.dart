import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// ════════════════════════════════════════════════════════════════════
///  Uygulama içi tam-ekran alarm sistemi.
///  - Kilit ekranında çalar (fullScreenIntent)
///  - Ses + titreşim döngüsü
///  - Ertele / Kapat aksiyonları
///  - Mesai çıkış entegrasyonu için özel payload
/// ════════════════════════════════════════════════════════════════════

/// Alarm türleri.
enum AlarmKind { schedule, shiftCheckout }

/// Çalan alarm verisi (UI'a iletilir).
class RingingAlarm {
  final int id;
  final String title;
  final String body;
  final AlarmKind kind;
  final int? refId; // schedule entry id veya shift id

  const RingingAlarm({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.refId,
  });
}

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;

  /// Alarm çaldığında UI'ı açmak için global stream.
  final StreamController<RingingAlarm> _ringController =
      StreamController<RingingAlarm>.broadcast();
  Stream<RingingAlarm> get onAlarmRing => _ringController.stream;

  static const String _channelId = 'alarm_fullscreen';

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );

    // Yüksek öncelikli, tam ekran alarm kanalı.
    const channel = AndroidNotificationChannel(
      _channelId,
      'Alarmlar',
      description: 'Çalışma programı ve mesai alarmları',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(channel);
    // İzinleri iste: bildirim + tam zamanlı alarm.
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Tam ekran alarm bildirimi göster + ses + titreşim başlat.
  Future<void> fireAlarm(RingingAlarm alarm) async {
    await init();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      'Alarmlar',
      channelDescription: 'Çalışma programı ve mesai alarmları',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true, // kilit ekranını uyandırır
      ongoing: true,
      autoCancel: false,
      playSound: true, // sistem sesi (AudioPlayer'a ek güvence)
      enableVibration: true,
      visibility: NotificationVisibility.public,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('alarm_snooze', 'Ertele (5 dk)'),
        AndroidNotificationAction(
          alarm.kind == AlarmKind.shiftCheckout ? 'shift_finish' : 'alarm_dismiss',
          alarm.kind == AlarmKind.shiftCheckout ? 'Çıkış Yap' : 'Kapat',
          cancelNotification: true,
        ),
      ],
    );

    final payload = '${alarm.kind.name}:${alarm.id}:${alarm.refId ?? ''}';
    await _plugin.show(
      alarm.id,
      alarm.title,
      alarm.body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );

    await _startRingingEffects();
    _ringController.add(alarm);
  }

  /// Tam ekran alarm bildirim detayları (planlı alarmlar için ortak).
  AndroidNotificationDetails _alarmDetails(AlarmKind kind) {
    return AndroidNotificationDetails(
      _channelId,
      'Alarmlar',
      channelDescription: 'Çalışma programı ve mesai alarmları',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT (ses tekrar)
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction('alarm_snooze', 'Ertele (5 dk)'),
        AndroidNotificationAction(
          kind == AlarmKind.shiftCheckout ? 'shift_finish' : 'alarm_dismiss',
          kind == AlarmKind.shiftCheckout ? 'Çıkış Yap' : 'Kapat',
          cancelNotification: true,
        ),
      ],
    );
  }

  String _payload(AlarmKind kind, int id, int? refId) =>
      '${kind.name}:$id:${refId ?? ''}';

  /// Belirli bir tarihte tam ekran alarm planla (tek seferlik).
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required AlarmKind kind,
    int? refId,
  }) async {
    await init();
    final tzWhen = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzWhen,
      NotificationDetails(android: _alarmDetails(kind)),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _payload(kind, id, refId),
    );
  }

  /// N süre sonra tam ekran alarm (test için).
  Future<void> scheduleOnceAfter({
    required int id,
    required Duration delay,
    required String title,
    required String body,
    required AlarmKind kind,
    int? refId,
  }) async {
    await scheduleAt(
      id: id,
      when: DateTime.now().add(delay),
      title: title,
      body: body,
      kind: kind,
      refId: refId,
    );
  }

  /// Haftalık tekrarlı tam ekran alarm — her hafta aynı gün/saat.
  Future<void> scheduleWeekly({
    required int id,
    required int weekday, // 1=Pzt..7=Paz
    required int hour,
    required int minute,
    required String title,
    required String body,
    required AlarmKind kind,
    int? refId,
  }) async {
    await init();
    final when = _nextWeekdayTime(weekday, hour, minute);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      NotificationDetails(android: _alarmDetails(kind)),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: _payload(kind, id, refId),
    );
  }

  /// Bir sonraki [weekday] gününün [hour]:[minute] tz zamanı.
  tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    while (d.weekday != weekday || d.isBefore(now)) {
      d = d.add(const Duration(days: 1));
      d = tz.TZDateTime(tz.local, d.year, d.month, d.day, hour, minute);
    }
    return d;
  }

  Future<void> cancelScheduled(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  /// Ses + titreşim döngüsü başlat.
  Future<void> _startRingingEffects() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      // Cihaz alarm sesini döngüde çal.
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      // alarm.mp3 varsa onu, yoksa mevcut beep sesini döngüde çal.
      try {
        await _player.play(AssetSource('sounds/alarm.mp3'));
      } catch (_) {
        await _player.play(AssetSource('sounds/beep_product.wav'));
      }
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(
          pattern: [0, 800, 500, 800, 500, 800, 500],
          repeat: 0, // sürekli tekrar
        );
      }
    } catch (_) {}
  }

  /// Ses + titreşimi durdur, wakelock bırak.
  Future<void> stopRinging() async {
    try { await _player.stop(); } catch (_) {}
    try { Vibration.cancel(); } catch (_) {}
    try { await WakelockPlus.disable(); } catch (_) {}
  }

  /// Alarmı tamamen kapat.
  Future<void> dismiss(int notifId) async {
    await stopRinging();
    await _plugin.cancel(notifId);
  }

  /// 5 dakika ertele.
  Future<void> snooze(RingingAlarm alarm) async {
    await stopRinging();
    await _plugin.cancel(alarm.id);
    // 5 dk sonra tekrar çal.
    Timer(const Duration(minutes: 5), () => fireAlarm(alarm));
  }

  void _onResponse(NotificationResponse resp) {
    final action = resp.actionId;
    final payload = resp.payload ?? '';
    final parts = payload.split(':');
    if (parts.length < 2) return;
    final kind = parts[0];
    final notifId = int.tryParse(parts[1]) ?? 0;
    final refId = parts.length > 2 ? int.tryParse(parts[2]) : null;

    if (action == 'alarm_snooze') {
      final alarm = RingingAlarm(
        id: notifId,
        title: 'Alarm',
        body: '',
        kind: kind == 'shiftCheckout'
            ? AlarmKind.shiftCheckout
            : AlarmKind.schedule,
        refId: refId,
      );
      snooze(alarm);
    } else if (action == 'shift_finish') {
      stopRinging();
      _plugin.cancel(notifId);
      onShiftFinishRequested?.call(refId ?? 0);
    } else {
      // dismiss veya bildirime dokunma
      stopRinging();
      _plugin.cancel(notifId);
      if (action == null) {
        // Bildirime dokundu → alarm ekranını aç.
        _ringController.add(RingingAlarm(
          id: notifId,
          title: 'Alarm',
          body: '',
          kind: kind == 'shiftCheckout'
              ? AlarmKind.shiftCheckout
              : AlarmKind.schedule,
          refId: refId,
        ));
      }
    }
  }

  // Mesai "Çıkış Yap" aksiyonu callback'i.
  static void Function(int shiftId)? onShiftFinishRequested;
}
