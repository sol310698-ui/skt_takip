import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// "Evrenler arasi gecis" animasyonlu route.
/// Mevcut ekran kucuk bir noktaya buzulup kararir, hedef ekran
/// derinlikten buyuyerek acilir — solucan deligi/warp hissi.
class UniverseTransition extends PageRouteBuilder {
  final Widget page;

  UniverseTransition({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 650),
          reverseTransitionDuration: const Duration(milliseconds: 550),
          opaque: true,
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, animation, secondary, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // Hedef ekran: derinlikten (0.0) buyuyerek + donerek gelir.
            final scale = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
            final rotate =
                Tween<double>(begin: 0.18, end: 0.0).animate(curved);
            final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.25, 1.0,
                      curve: Curves.easeIn)),
            );

            return Stack(
              children: [
                // Arkada "uzay" zemini parlamasi.
                FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0).animate(
                    CurvedAnimation(
                        parent: animation,
                        curve: const Interval(0.0, 0.5)),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.accent.withOpacity(0.4),
                          AppTheme.primary.withOpacity(0.15),
                          Colors.black,
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: fade,
                  child: RotationTransition(
                    turns: rotate,
                    child: ScaleTransition(scale: scale, child: child),
                  ),
                ),
              ],
            );
          },
        );
}
