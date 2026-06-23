import 'package:flutter/material.dart';

import '../../core/nav_bar_visibility.dart';
import '../../core/theme/app_theme.dart';

/// Tek bir aksiyon ogesi (speed-dial menusunde bir secenek).
class SpeedDialAction {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const SpeedDialAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
}

/// ════════════════════════════════════════════════════════════════════
///  Animasyonlu Speed-Dial FAB.
///
///  Aksiyonlar ana (+) butonun TAM USTUNDE, ayni Column icinde dizilir.
///  Boylece konum cakismasi IMKANSIZ - Flutter layout sistemi hizalar.
///  Karartma, FAB'in arkasinda tum ekrani kaplayan bir katmandir.
/// ════════════════════════════════════════════════════════════════════
class SpeedDialFab extends StatefulWidget {
  final List<SpeedDialAction> actions;
  final Color? backgroundColor;
  final IconData icon;

  /// Alttaki nav bar icin FAB'i yukari iten bosluk.
  final double bottomOffset;

  const SpeedDialFab({
    super.key,
    required this.actions,
    this.backgroundColor,
    this.icon = Icons.add_rounded,
    this.bottomOffset = 96,
  });

  @override
  State<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<SpeedDialFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppTheme.primary;
    // Tum ekrani kaplayan Stack: karartma + sag altta FAB/aksiyon kolonu.
    return Stack(
      children: [
        // Karartma (sadece acikken, dokununca kapatir).
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Container(
                  color: Colors.black.withOpacity(0.5 * _ctrl.value),
                ),
              ),
            ),
          ),
        // Sag altta: aksiyonlar (ustte) + ana FAB (altta) AYNI kolonda.
        // Nav bar ile SENKRON: nav bar gizlenince (asagi kaydirinca) bu FAB
        // de ayni sure/egriyle asagi inip onunla birlikte ekran disina cikar;
        // acilinca geri yukari gelir. Boylece floating nav bar ile cakismaz.
        Positioned(
          right: 16,
          bottom: 16 + widget.bottomOffset,
          child: ValueListenableBuilder<bool>(
            valueListenable: navBarVisible,
            builder: (_, navVisible, child) => AnimatedSlide(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              offset: navVisible ? Offset.zero : const Offset(0, 1.6),
              child: child,
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Aksiyonlar (animasyonlu acilir).
              ...List.generate(widget.actions.length, (i) {
                final action = widget.actions[i];
                final anim = CurvedAnimation(
                  parent: _ctrl,
                  curve: Curves.easeOutBack,
                );
                return SizeTransition(
                  sizeFactor: anim,
                  axisAlignment: 1.0,
                  child: FadeTransition(
                    opacity: _ctrl,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _actionRow(action),
                    ),
                  ),
                );
              }),
              // Ana (+) buton - HER ZAMAN aksiyonlarin ALTINDA.
              // Soft Glass: duz renk yerine pastel gradyan + yumusak golge.
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                elevation: 0,
                child: InkWell(
                  onTap: _toggle,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [bg, bg.withOpacity(0.75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: AppTheme.glow(bg),
                    ),
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => Transform.rotate(
                        angle: _ctrl.value * 0.785398, // 45° -> x
                        child: Icon(widget.icon, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ],
    );
  }

  Widget _actionRow(SpeedDialAction action) {
    final color = action.color ?? AppTheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Etiket
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            action.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        // Mini buton
        FloatingActionButton.small(
          heroTag: 'sd_${action.label}',
          onPressed: () {
            _close();
            action.onTap();
          },
          backgroundColor: color,
          foregroundColor:
              color == AppTheme.accent ? Colors.black : Colors.white,
          elevation: 3,
          child: Icon(action.icon, size: 22),
        ),
      ],
    );
  }
}
