import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_constants.dart';
import 'core/services/alarm_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/schedule_service.dart';
import 'core/services/skt_alarm_settings.dart';
import 'core/theme/app_theme.dart';
import 'views/screens/alarm_ring_screen.dart';
import 'views/screens/main_shell.dart';
import 'views/screens/skt_disposal_alarm_screen.dart';

/// Global navigator — alarm caldiginda ekrani acmak icin.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr', null);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Uygulamayi yalnizca DIKEY moda kilitle (yatay moda asla gecmesin).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Alarm paketini baslat (kilit ekrani alarmi icin).
  await AlarmService.init();
  // Gerekli izinleri iste (bildirim + tam zamanli alarm).
  await AlarmService.requestPermissions();

  // SKT imha alarmi acik ise, gunluk zincirin kopmamasi icin her
  // uygulama acilisinda bir sonraki olusuma yeniden kur (sessizce).
  _ensureSktDisposalAlarm();

  runApp(const ProviderScope(child: SktTakipApp()));

  // Bildirim servisini arka planda baslat.
  NotificationService.instance.init();
}

/// SKT imha alarmi etkinse, bir sonraki gun/saate kurulu oldugundan emin ol.
Future<void> _ensureSktDisposalAlarm() async {
  try {
    final on = await SktAlarmSettings.instance.isEnabled();
    if (!on) return;
    final h = await SktAlarmSettings.instance.getHour();
    final m = await SktAlarmSettings.instance.getMinute();
    await ScheduleService.instance.setSktDisposalAlarm(hour: h, minute: m);
  } catch (_) {}
}

class SktTakipApp extends StatefulWidget {
  const SktTakipApp({super.key});

  @override
  State<SktTakipApp> createState() => _SktTakipAppState();
}

class _SktTakipAppState extends State<SktTakipApp> {
  StreamSubscription? _ringSub;

  @override
  void initState() {
    super.initState();
    // Alarm caldiginda: kendi alarm ekranimizi ac + haftalik tekrar kur.
    _ringSub = Alarm.ringing.listen((alarmSet) {
      for (final alarm in alarmSet.alarms) {
        _onAlarmRing(alarm.id, alarm.notificationSettings.title,
            alarm.notificationSettings.body);
      }
    });
  }

  void _onAlarmRing(int id, String title, String body) {
    // Haftalik program alarmiysa bir sonraki haftaya yeniden kur.
    ScheduleService.instance.rescheduleIfWeekly(id);

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // SKT imha alarmi (sabit ID) -> ozel ekran.
    if (id == ScheduleService.sktDisposalAlarmId) {
      nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SktDisposalAlarmScreen(
          alarmId: id,
          onGoToList: () {
            // SKT listesine (ana ekran) yonlendir.
            navigatorKey.currentState?.popUntil((r) => r.isFirst);
          },
        ),
      ));
      return;
    }

    // Kendi modern alarm ekranimizi goster.
    final isShift = id >= 800000 && id < 900000;
    nav.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AlarmRingScreen(
        alarmId: id,
        title: title,
        body: body,
        isShift: isShift,
        shiftId: isShift ? id - 800000 : null,
      ),
    ));
  }

  @override
  void dispose() {
    _ringSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const MainShell(),
    );
  }
}
