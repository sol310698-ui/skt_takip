import 'package:flutter/material.dart';

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
///  Tek (+) butonu; basinca yukari dogru etiketli aksiyonlar acilir.
///  - (+) ikonu 45° doner (x'e donusur)
///  - Aksiyonlar sirayla fade + scale + slide ile belirir
///  - Arka plan hafifce kararir (disari dokununca kapanir)
/// ════════════════════════════════════════════════════════════════════
class SpeedDialFab extends StatefulWidget {
  final List<SpeedDialAction> actions;
  final Color? backgroundColor;
  final IconData icon;

  const SpeedDialFab({
    super.key,
    required this.actions,
    this.backgroundColor,
    this.icon = Icons.add_rounded,
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
        vsync: this, duration: const Duration(milliseconds: 280));
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
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Arka plan karartma (acikken, disari dokununca kapatir).
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Container(
                  color: Colors.black.withOpacity(0.45 * _ctrl.value),
                ),
              ),
            ),
          ),
        // Aksiyonlar + ana buton
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Aksiyon ogeleri (yukaridan asagiya, sondan basa animasyon).
              ...List.generate(widget.actions.length, (i) {
                final action = widget.actions[i];
                // Her oge biraz gecikmeli belirir.
                final start = i / (widget.actions.length * 2);
                final anim = CurvedAnimation(
                  parent: _ctrl,
                  curve: Interval(start, 1.0, curve: Curves.easeOutBack),
                );
                return SizeTransition(
                  sizeFactor: CurvedAnimation(
                      parent: _ctrl, curve: Curves.easeOut),
                  axisAlignment: 1.0,
                  child: FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: anim,
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _actionRow(action),
                      ),
                    ),
                  ),
                );
              }),
              // Ana (+) buton
              FloatingActionButton(
                heroTag: 'speeddial_main',
                onPressed: _toggle,
                backgroundColor: bg,
                foregroundColor: Colors.white,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => Transform.rotate(
                    angle: _ctrl.value * 0.785398, // 45°
                    child: Icon(widget.icon),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionRow(SpeedDialAction action) {
    final color = action.color ?? AppTheme.surface;
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
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            action.label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
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
