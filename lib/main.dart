import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_constants.dart';
import 'core/services/alarm_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'views/screens/alarm_ring_screen.dart';
import 'views/screens/main_shell.dart';

/// Global navigator — alarm çaldığında ekranı açmak için.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr', null);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));


  runApp(const ProviderScope(child: SktTakipApp()));

  // Servisleri arka planda başlat.
  NotificationService.instance.init();
  AlarmService.instance.init();
  // İlk frame sonrası: uygulama bir alarmla açıldıysa ekranı göster.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await AlarmService.instance.init();
    await Future.delayed(const Duration(milliseconds: 300));
    await AlarmService.instance.checkLaunchedByAlarm();
  });
}

class SktTakipApp extends StatefulWidget {
  const SktTakipApp({super.key});

  @override
  State<SktTakipApp> createState() => _SktTakipAppState();
}

class _SktTakipAppState extends State<SktTakipApp> {
  StreamSubscription<RingingAlarm>? _alarmSub;

  @override
  void initState() {
    super.initState();
    // Alarm çaldığında tam ekran alarm ekranını aç.
    _alarmSub = AlarmService.instance.onAlarmRing.listen((alarm) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlarmRingScreen(alarm: alarm),
      ));
    });
  }

  @override
  void dispose() {
    _alarmSub?.cancel();
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
