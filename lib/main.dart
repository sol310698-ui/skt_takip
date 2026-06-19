import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_constants.dart';
import 'core/services/alarm_flow.dart';
import 'core/services/alarm_service.dart';
import 'core/services/app_logger.dart';
import 'core/services/notification_service.dart';
import 'core/services/schedule_service.dart';
import 'core/services/skt_alarm_settings.dart';
import 'core/theme/app_theme.dart';
import 'views/screens/main_shell.dart';

/// Global navigator — alarm caldiginda ekrani acmak icin.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr', null);
  await AppLogger.instance
      .log('APP', 'main() basladi (uygulama/izolat ayaga kalkti).');

  // Edge-to-edge: icerik status bar'in ARKASINA uzanir.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  ));

  // Uygulamayi yalnizca DIKEY moda kilitle.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── ALARM BASLATMA SIRASI ──
  // 1) Paketi baslat.
  await AlarmService.init();
  // 2) Sorunlu (mp3 disi) genel ses ayarini temizle (eski .wav kayitlari
  //    alarmi sessiz birakip ekran acmiyordu).
  final sanitized = await SktAlarmSettings.instance.sanitizeSoundIfNeeded();
  if (sanitized) {
    await AppLogger.instance.log(
        'ALARM', 'Sorunlu ses ayari temizlendi -> varsayilan sese donuldu.');
  }
  // 3) Izinleri iste (bildirim + tam zamanli alarm + tam ekran intent).
  await AlarmService.requestPermissions();
  // 4) Alarm calma akisini baslat (dinleyici runApp'ten ONCE kurulur ki
  //    soguk baslatmada ilk ringing event'i kaybolmasin).
  AlarmFlow.instance.start(navigatorKey);

  // 5) Acilis guvenceleri (zincirlerin kurulu oldugundan emin ol).
  _ensureSktDisposalAlarm();
  _ensureWeeklyAlarms();
  _ensureKeepAlive();

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
    final m = await SktAlarmSettings.instance.getMinute();    await ScheduleService.instance.setSktDisposalAlarm(hour: h, minute: m);
  } catch (_) {}
}

/// Tum aktif haftalik alarmlari yeniden kur (reboot/acilis guvencesi).
Future<void> _ensureWeeklyAlarms() async {
  try {
    await ScheduleService.instance.refreshAllAlarms();
  } catch (_) {}
}

/// Kullanici kalici servisi (swipe-kill korumasi) actiysa baslat.
Future<void> _ensureKeepAlive() async {
  try {
    if (await SktAlarmSettings.instance.isKeepAliveOn()) {
      await AlarmService.startKeepAlive();
    }
  } catch (_) {}
}

class SktTakipApp extends StatefulWidget {
  const SktTakipApp({super.key});

  @override
  State<SktTakipApp> createState() => _SktTakipAppState();
}

class _SktTakipAppState extends State<SktTakipApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Ilk frame cizildikten sonra (navigator hazir olunca) bekleyen alarmi
    // kontrol et. Uygulama alarm tarafindan soguk baslatildiysa AlarmFlow
    // bekleyen alarmi tutar ve burada gosterir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlarmFlow.instance.onUiReady();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama one geldiginde bekleyen alarm varsa goster.
    if (state == AppLifecycleState.resumed) {
      AlarmFlow.instance.onUiReady();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
