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
///  Karartma katmani Overlay ile cizilir (yerlesim tasmaz).
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
  OverlayEntry? _overlay;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
  }

  @override
  void dispose() {
    _removeOverlay();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openMenu();
    }
  }

  void _openMenu() {
    _overlay = _buildOverlay();
    Overlay.of(context).insert(_overlay!);
    setState(() => _open = true);
    _ctrl.forward();
  }

  void _close() {
    _ctrl.reverse().then((_) => _removeOverlay());
    setState(() => _open = false);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  OverlayEntry _buildOverlay() {
    return OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Karartma (disari dokununca kapatir).
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
            // Aksiyonlar (sag altta, ana FAB'in hemen ustunde).
            Positioned(
              right: 16,
              bottom: 16 + 56 + 16, // padding + FAB yuksekligi + bosluk
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.actions.length, (i) {
                  final action = widget.actions[i];
                  final start = i / (widget.actions.length * 2 + 1);
                  final anim = CurvedAnimation(
                    parent: _ctrl,
                    curve: Interval(start, 1.0, curve: Curves.easeOutBack),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: anim,
                        alignment: Alignment.centerRight,
                        child: _actionRow(action),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppTheme.primary;
    // Sadece ana (+) buton; aksiyonlar Overlay'de.
    return FloatingActionButton(
      heroTag: 'speeddial_main',
      onPressed: _toggle,
      backgroundColor: bg,
      foregroundColor: Colors.white,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.rotate(
          angle: _ctrl.value * 0.785398, // 45° -> x
          child: Icon(widget.icon),
        ),
      ),
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
