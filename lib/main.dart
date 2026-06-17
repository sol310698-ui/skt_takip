import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

/// Soguk baslatmada yakalanan ama henuz gosterilemeyen alarm.
int? _pendingAlarmId;
String _pendingTitle = '';
String _pendingBody = '';
StreamSubscription? _globalRingSub;
/// Alarm ekrani su an acik mi? (Ust uste activity acilmasini onler.)
bool _alarmScreenOpen = false;
/// O an gosterilen alarm ID (ayni alarmi tekrar acmamak icin).
int? _shownAlarmId;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr', null);
  // Edge-to-edge: icerik status bar'in ARKASINA uzanir (mor banner gorunur).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
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

  // ÖNEMLİ: Alarm dinleyicisini runApp'ten ÖNCE kur. Boylece uygulama
  // alarm tarafindan soguk baslatildiginda bile ilk event yakalanir.
  // Yakalanan alarm _pendingAlarmId'ye yazilir; arayuz hazir olunca acilir.
  _globalRingSub = Alarm.ringing.listen((alarmSet) {
    // KRITIK: Alarm caldigi an CPU/ekrani ZORLA uyanik tut. Doze modunda
    // islemcinin durup sesi kesmesini engeller. Alarm durdurulunca birakilir.
    if (alarmSet.alarms.isNotEmpty) {
      WakelockPlus.enable();
    }
    for (final alarm in alarmSet.alarms) {
      _pendingAlarmId = alarm.id;
      _pendingTitle = alarm.notificationSettings.title;
      _pendingBody = alarm.notificationSettings.body;
      // Arayuz aciksa hemen goster.
      _tryShowPendingAlarm();
    }
  });

  // SKT imha alarmi acik ise, gunluk zincirin kopmamasi icin her
  // uygulama acilisinda bir sonraki olusuma yeniden kur (sessizce).
  _ensureSktDisposalAlarm();
  // Reboot sonrasi guvence: tum aktif haftalik alarmlari yeniden kur.
  // (Uygulama acildiginda alarmlarin kurulu oldugundan emin oluruz.)
  _ensureWeeklyAlarms();
  // Kullanici kalici servisi actiysa baslat (swipe-kill korumasi).
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

/// Bekleyen alarm varsa ve arayuz hazirsa, dogru alarm ekranini ac.
void _tryShowPendingAlarm() {
  final id = _pendingAlarmId;
  if (id == null) return;
  final nav = navigatorKey.currentState;
  if (nav == null) return; // arayuz henuz hazir degil; sonra denenecek

  // ── UST USTE ACILMA KORUMASI ──
  // Zaten bir alarm ekrani aciksa, tekrar acma (activity ust uste binmesin).
  if (_alarmScreenOpen) {
    // Ayni alarmsa tuket ve cik; farkli alarmsa beklet (mevcut kapaninca acilir).
    if (_shownAlarmId == id) _pendingAlarmId = null;
    return;
  }

  // Tuketildi olarak isaretle (tekrar acilmasin).
  _pendingAlarmId = null;
  _alarmScreenOpen = true;
  _shownAlarmId = id;
  final title = _pendingTitle;
  final body = _pendingBody;

  // Haftalik program alarmiysa bir sonraki haftaya yeniden kur.
  ScheduleService.instance.rescheduleIfWeekly(id);

  // SKT imha alarmi (sabit ID) -> ozel ekran.
  if (id == ScheduleService.sktDisposalAlarmId) {
    nav
        .push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SktDisposalAlarmScreen(
            alarmId: id,
            onGoToList: () {
              navigatorKey.currentState?.popUntil((r) => r.isFirst);
            },
          ),
        ))
        .then((_) {
      // Ekran kapandi -> bayraklari sifirla (sonraki alarm acilabilsin).
      _alarmScreenOpen = false;
      _shownAlarmId = null;
      _tryShowPendingAlarm(); // bekleyen baska alarm varsa ac
    });
    return;
  }

  // Haftalik / mesai alarmi -> modern alarm ekrani.
  final isShift = id >= 800000 && id < 900000;
  nav
      .push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlarmRingScreen(
          alarmId: id,
          title: title,
          body: body,
          isShift: isShift,
          shiftId: isShift ? id - 800000 : null,
        ),
      ))
      .then((_) {
    _alarmScreenOpen = false;
    _shownAlarmId = null;
    _tryShowPendingAlarm();
  });
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
    // Ilk frame cizildikten sonra (navigator hazir olunca) bekleyen
    // alarmi kontrol et. Uygulama alarm tarafindan soguk baslatildiysa
    // _pendingAlarmId dolu olur ve dogru alarm ekrani acilir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryShowPendingAlarm();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama one geldiginde bekleyen alarm varsa goster.
    if (state == AppLifecycleState.resumed) {
      _tryShowPendingAlarm();
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
