import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_constants.dart';
import 'core/services/alarm_flow.dart';
import 'core/services/alarm_service.dart';
import 'core/services/app_lock_service.dart';
import 'core/services/app_logger.dart';
import 'core/services/notification_service.dart';
import 'core/services/schedule_service.dart';
import 'core/services/skt_alarm_settings.dart';
import 'core/theme/app_theme.dart';
import 'views/screens/lock_screen.dart';
import 'views/screens/main_shell.dart';

/// Global navigator — alarm caldiginda ekrani acmak icin.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr', null);
  await AppLogger.instance
      .log('APP', 'main() basladi (uygulama/izolat ayaga kalkti).');

  // Tam ekran (immersive sticky): status bar VE sistem navigasyon cubugu
  // tamamen gizlenir. Kullanici ekranin ustunden/altindan kaydirirsa
  // gecici gorunur, sonra otomatik tekrar gizlenir (sticky davranis).
  // ONEMLI: await edilmezse native taraf isareti islemeden runApp()
  // calisabiliyor, bu da ilk acilista status bar'in (siyah serit olarak)
  // bir an / surekli gorunmesine sebep oluyordu.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
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
  // Uygulama her acilista (soguk baslatma) ve her arka plandan one
  // gelirken (resumed) kilit ekrani gosterilir. Sadece kullanici basariyla
  // PIN/biyometri ile dogrulanirsa _locked = false olur.
  bool _locked = true;
  bool _lockCheckDone = false;

  // Uygulama ne zaman ARKA PLANA gittigini (paused) izaretlemek icin.
  // Biyometri (BiometricPrompt) dialogu acilirken sistem kisa bir
  // "paused/inactive" sinyali gonderir, hemen ardindan "resumed" gelir.
  // Bu DOGAL gecisi "arka plandan gerciden geri donus" ile ayirt
  // ETMEZSEK, biyometri basarili olup kilit acildiginda bile resumed
  // tekrar tetiklenip kilidi yeniden kapatiyor, LockScreen yeniden
  // kuruluyor, initState tekrar biyometriyi otomatik aciyor — SONSUZ
  // DONGU (kullanicinin bildirdigi "surekli parmak izi soruyor" hatasi
  // tam olarak buydu).
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockOnStart();
    // Ilk frame cizildikten sonra (navigator hazir olunca) bekleyen alarmi
    // kontrol et. Uygulama alarm tarafindan soguk baslatildiysa AlarmFlow
    // bekleyen alarmi tutar ve burada gosterir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AlarmFlow.instance.onUiReady();
      // Tam ekran modunu ilk frame ciziminden SONRA bir kez daha zorla.
      // main()'deki tek seferlik cagri bazi cihazlarda ilk layout
      // tarafindan ezilebiliyor; burada tekrar etmek bunu garantiler.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
  }

  Future<void> _checkLockOnStart() async {
    final enabled = await AppLockService.instance.isLockEnabled();
    if (!mounted) return;
    setState(() {
      _locked = enabled; // kilit kapaliysa direkt acik say
      _lockCheckDone = true;
    });
  }

  void _onUnlocked() {
    if (mounted) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Uygulama one geldiginde bekleyen alarm varsa goster.
      AlarmFlow.instance.onUiReady();

      // Tam ekran modu bazi cihazlarda/eklentilerde (kamera, sistem
      // dialoglari vb.) arka plana gidip gelince sifirlanabiliyor.
      // One her gelindiginde yeniden uygulayarak garanti ediyoruz.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      // KRITIK: sadece GERCEKTEN bir sure arka planda kalindiysa kilitle.
      // Biyometri/izin dialogu gibi anlik sistem gecisleri ~1 saniyenin
      // altinda surer; bu kisa gecisleri kilitleme tetikleyicisi SAYMIYORUZ.
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null) {
        final elapsed = DateTime.now().difference(pausedAt);
        if (elapsed > const Duration(seconds: 2)) {
          _relockIfNeeded();
        }
      }
    }
  }

  Future<void> _relockIfNeeded() async {
    final enabled = await AppLockService.instance.isLockEnabled();
    if (enabled && mounted && !_locked) {
      setState(() => _locked = true);
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
      home: !_lockCheckDone
          ? const Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(child: CircularProgressIndicator()),
            )
          : (_locked
              ? LockScreen(onUnlocked: _onUnlocked)
              : const MainShell()),
    );
  }
}
