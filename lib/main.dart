import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_constants.dart';
import 'core/services/alarm_flow.dart';
import 'core/services/alarm_service.dart';
import 'core/services/db_source_prefs.dart';
import 'core/services/flow_prefs.dart';
import 'core/services/theme_prefs.dart';
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

  // ── GLOBAL LOG YAKALAMA ──────────────────────────────────────────────
  // Amac: uygulamanin HER yerindeki debugPrint/print ciktilari ve TUM
  // yakalanmamis hatalar (exception + stack) otomatik olarak AppLogger'a
  // (kalici dosyaya) dussun. Boylece log ekrani "tum uygulama loglarini"
  // gosterir — her yere elle log koymaya gerek kalmaz.

  // 1) debugPrint'i sar: hem konsola yaz hem log dosyasina ekle.
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) {
      AppLogger.instance.log('PRINT', message);
    }
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };

  // 2) Flutter framework hatalari (widget build hatalari vb.).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.instance.log(
      'FLUTTER_HATA',
      '${details.exceptionAsString()}\n${details.stack ?? ""}',
    );
  };

  // 3) Framework disi (async) yakalanmamis hatalar.
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.log('HATA', '$error\n$stack');
    return true; // hata isle, uygulamayi coketme.
  };

  await initializeDateFormatting('tr', null);
  await AppLogger.instance
      .log('APP', 'main() basladi (uygulama/izolat ayaga kalkti).');

  // EDGE-TO-EDGE: status bar GIZLENMIYOR, seffaf birakiliyor ve uygulama
  // icerigi (banner gradient / AppBar) onun arkasina uzaniyor. Boylece
  // status bar ust bardaki renkle ayni gorunur, siyah serit OLMAZ.
  // Eski immersiveSticky (tam gizleme) yaklasimi Xiaomi/MIUI'de siyah serit
  // birakiyordu — kaldirildi. Native taraf (styles.xml + MainActivity) bu
  // edge-to-edge davranisini ayrica garanti eder.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  // 6) Hizli akis tercihini yukle (SKT Tara ekranindaki toggle hatirlanir).
  await FlowPrefs.instance.load();

  // 6b) Veri tabani kaynak tercihlerini yukle (OFF/OBF — barkod sorgulari
  //     icin hangi acik veri tabanlarinin aktif oldugu).
  await DbSourcePrefs.instance.load();

  // 7) Tema tercihini yukle (Aydinlik/Koyu/Sistem).
  await ThemePrefs.instance.load();
  AppTheme.applyBrightness(ThemePrefs.instance.mode == ThemeMode.light);

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
  // Kilit acildiginda hangi sekmeyle acilacak (3=Mesai, kullanici is
  // yerindeyse). Varsayilan 0 = Anasayfa.
  int _initialNavIndex = 0;

  // Uygulama arka plana gitti mi? (Pause/inactive olayinda set edilir,
  // resume'da okunup temizlenir.) Artik SUREYI degil, sadece "bir pause
  // yasandi mi" bilgisini tutar; kilit karari niyet sayacindan verilir
  // (AppLockService.consumeIsSystemActivityResume).
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

  void _onUnlocked({bool goToShift = false}) {
    if (mounted) {
      setState(() {
        _initialNavIndex = goToShift ? 3 : 0;
        _locked = false;
      });
    }
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
      // NOT: tam ekran modu artik Dart'tan degil, MainActivity.kt'deki
      // onResume/onWindowFocusChanged tarafindan native olarak yonetiliyor.

      final wasPaused = _pausedAt != null;
      _pausedAt = null;

      // ─── KILIT KARARI (niyet tabanli, kusursuz) ───
      //
      // Bu resume, uygulamanin KENDI actigi bir sistem ekranindan mi
      // (kamera/galeri/biyometri) donus, yoksa kullanicinin uygulamayi
      // GERCEKTEN arka plana alip donmesi mi? Bunu SUREYE bakarak tahmin
      // ETMIYORUZ (kirilgan); dogrudan niyet sayacindan OKUYORUZ.
      //
      //  - Uygulama ici islem donusu  -> KILITLEME (akis kesilmesin).
      //  - Gercek arka plandan donus   -> kilit aciksa KILITLE (guvenlik).
      //
      // Hic pause olmadan gelen resume (orn. ilk acilis, ic state degisimi)
      // de kilitleme tetiklemez.
      if (!wasPaused) return;

      final isAppActivityReturn =
          AppLockService.consumeIsSystemActivityResume();
      if (isAppActivityReturn) {
        // Uygulama ici kamera/galeri/biyometri donusu — kilit yok.
        return;
      }

      // Gercek arka plandan donus: guvenlik icin kilitle.
      _relockIfNeeded();
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
    return AnimatedBuilder(
      animation: ThemePrefs.instance,
      builder: (context, _) {
        // Aktif renk paletini, GOSTERILECEK temaya gore onceden ayarla.
        // (Statik AppTheme renkleri ile gosterilen ThemeData ayni palette
        //  olmali; bu yuzden MaterialApp kurulmadan once dogru paleti set
        //  ediyoruz.)
        final mode = ThemePrefs.instance.mode;
        final platformLight = MediaQuery.maybeOf(context)?.platformBrightness ==
            Brightness.light;
        final useLight = switch (mode) {
          ThemeMode.light => true,
          ThemeMode.dark => false,
          ThemeMode.system => platformLight,
        };
        AppTheme.applyBrightness(useLight);
        // Kullanicinin sectigi ana rengi uygula (butonlar, vurgular...).
        AppTheme.setPrimary(ThemePrefs.instance.primaryColorValue);

        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemePrefs.instance.mode,
          builder: (context, child) {
            // MaterialApp icindeki gercek brightness'a gore paleti son kez
            // sabitle (system modunda dogru taraf secilsin).
            final isLight =
                Theme.of(context).brightness == Brightness.light;
            AppTheme.applyBrightness(isLight);
            return child ?? const SizedBox.shrink();
          },
          home: !_lockCheckDone
              ? Scaffold(
                  backgroundColor: AppTheme.background,
                  body: const Center(child: CircularProgressIndicator()),
                )
              : (_locked
                  ? LockScreen(onUnlocked: _onUnlocked)
                  : MainShell(initialNavIndex: _initialNavIndex)),
        );
      },
    );
  }
}
