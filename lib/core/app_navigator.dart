import 'package:flutter/material.dart';

/// Global navigator anahtari.
///
/// Cekirdek katmanda durur ki servisler (alarm akisi, asistan gezinme)
/// uygulamanin giris dosyasina (main.dart) bagimli olmadan ekran acabilsin.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Bu oturumda kilit BASARIYLA acildi mi? Tema degisiminde uygulama kendini
/// yeniden kurar (RestartWidget); bu bayrak sayesinde yeniden kurulumda kilit
/// ekrani TEKRAR gosterilmez (gercek soguk baslatmada surec sifirlandigi icin
/// bayrak yine false olur ve kilit istenir).
bool gSessionUnlocked = false;

/// ════════════════════════════════════════════════════════════════════
///  RESTART WIDGET — uygulamayi (tum widget agacini) tazeleyip yeniden kurar.
/// ────────────────────────────────────────────────────────────────────
///  Tema/vurgu rengi degisince cagrilir: AppTheme renkleri STATIK oldugu icin
///  o an gorunmeyen (yigindaki alt) ekranlar eski renkte kalabiliyordu.
///  Anahtari degistirip tum agaci yeniden kurmak, HER ekranin yeni temayi
///  okumasini garanti eder.
/// ════════════════════════════════════════════════════════════════════
class RestartWidget extends StatefulWidget {
  final Widget child;
  const RestartWidget({super.key, required this.child});

  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();
  void _restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
