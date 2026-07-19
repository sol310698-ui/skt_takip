import 'package:flutter/material.dart';

import '../../core/nav_bar_visibility.dart';
import '../../core/services/label_inspect_button_prefs.dart';
import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  ETİKET İNCELE FAB — Speed-Dial menüsünden ayrılıp SOL ALTA alınan,
///  bağımsız (tek başına) yuvarlak buton.
///
///  Diğer ana aksiyonlar (Etiket Bas / SKT Tara) sağ alttaki Speed-Dial
///  içinde kalır; bu buton sık kullanıldığı için tek dokunuşla, menü
///  açmadan erişilsin diye ayrı ve solda tutulur.
///
///  Dikkat çekmesi için hafif bir "nabız" (pulse) animasyonu oynatır.
///  Bu animasyon Ayarlar > Görünüm bölümünden açılıp kapatılabilir
///  (bkz. LabelInspectButtonPrefs). Kapatıldığında buton sabit durur.
/// ════════════════════════════════════════════════════════════════════
class LabelInspectFab extends StatefulWidget {
  final VoidCallback onTap;

  /// Alttaki nav bar / diğer sol alt butonlarla çakışmaması için pay.
  final double bottomOffset;

  const LabelInspectFab({
    super.key,
    required this.onTap,
    this.bottomOffset = 182,
  });

  @override
  State<LabelInspectFab> createState() => _LabelInspectFabState();
}

class _LabelInspectFabState extends State<LabelInspectFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    LabelInspectButtonPrefs.instance.addListener(_onPrefsChanged);
    _syncAnimation();
  }

  void _onPrefsChanged() => _syncAnimation();

  void _syncAnimation() {
    if (LabelInspectButtonPrefs.instance.animationEnabled) {
      _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LabelInspectButtonPrefs.instance.removeListener(_onPrefsChanged);
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.accent;
    return Positioned(
      left: 16,
      bottom: 16 + widget.bottomOffset,
      child: ValueListenableBuilder<bool>(
        valueListenable: navBarVisible,
        builder: (_, navVisible, child) => AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          offset: navVisible ? Offset.zero : const Offset(0, 1.6),
          child: child,
        ),
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) {
            final t = _pulseCtrl.value; // 0 -> 1 -> 0 (reverse ile)
            final scale = 1.0 + (t * 0.08);
            final glowStrength = 0.4 + (t * 0.5);
            return Transform.scale(
              scale: scale,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                elevation: 0,
                child: InkWell(
                  onTap: widget.onTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.75)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(glowStrength * 0.55),
                          blurRadius: 14 + (t * 10),
                          spreadRadius: t * 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.document_scanner_rounded,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
