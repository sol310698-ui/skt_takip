import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/label_inspect_visibility.dart';
import '../../core/nav_bar_visibility.dart';
import '../../core/services/label_inspect_button_prefs.dart';
import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  ETİKET İNCELE FAB — artık uygulamanın TÜM sayfalarında görünen,
///  bağımsız (menü açmadan her zaman erişilebilir) global bir yuvarlak
///  buton (bkz. main.dart: MaterialApp.builder içine eklenir).
///
///  Varsayılan konumu sağ altta, ana (+) speed-dial butonunun tam
///  üstüdür. Kullanıcı UZUN BASIP SÜRÜKLEYEREK butonu ekranın istediği
///  yerine taşıyabilir; bu özel konum kalıcı saklanır (bkz.
///  LabelInspectButtonPrefs) ve tüm sayfalarda aynı yerde kalır.
///
///  Dikkat çekmesi için hafif bir "nabız" (pulse) animasyonu oynatır.
///  Bu animasyon Ayarlar > Görünüm bölümünden açılıp kapatılabilir.
///  Kullanıcı zaten Etiket İncele ekranındaysa (labelInspectFabSuppressed)
///  buton otomatik gizlenir.
/// ════════════════════════════════════════════════════════════════════
class LabelInspectFab extends StatefulWidget {
  final VoidCallback onTap;

  /// Varsayılan (özel konum yokken) alttaki nav bar / + butonuyla
  /// çakışmaması için pay.
  final double bottomOffset;

  const LabelInspectFab({
    super.key,
    required this.onTap,
    this.bottomOffset = 178,
  });

  @override
  State<LabelInspectFab> createState() => _LabelInspectFabState();
}

class _LabelInspectFabState extends State<LabelInspectFab>
    with SingleTickerProviderStateMixin {
  static const _btnSize = 56.0;

  late final AnimationController _pulseCtrl;

  // Aktif surukleme sirasinda ekran-mutlak (px) konum; null = surukleme yok.
  Offset? _dragPos;
  bool _dragging = false;

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

  Offset _defaultTopLeft(Size screen, EdgeInsets safe) {
    return Offset(
      screen.width - 16 - _btnSize,
      screen.height - (16 + widget.bottomOffset + safe.bottom) - _btnSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: labelInspectFabSuppressed,
      builder: (_, suppressed, __) {
        if (suppressed) return const SizedBox.shrink();
        return _positioned(context);
      },
    );
  }

  Widget _positioned(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final safe = MediaQuery.of(context).padding;
    final prefs = LabelInspectButtonPrefs.instance;
    final hasCustom = prefs.hasCustomPosition;

    Offset topLeft;
    if (_dragPos != null) {
      topLeft = _dragPos!;
    } else if (hasCustom) {
      topLeft = Offset(
        prefs.posFx! * screen.width,
        prefs.posFy! * screen.height,
      );
    } else {
      topLeft = _defaultTopLeft(screen, safe);
    }
    // Ekran disina ve sistem cubuklarinin altina tasmasin.
    topLeft = Offset(
      topLeft.dx.clamp(0.0, screen.width - _btnSize),
      topLeft.dy.clamp(
          safe.top, screen.height - safe.bottom - _btnSize),
    );

    final color = AppTheme.accent;

    Widget button = AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final t = _pulseCtrl.value; // 0 -> 1 -> 0 (reverse ile)
        final pulseScale = 1.0 + (t * 0.08);
        final dragScale = _dragging ? 1.18 : 1.0;
        final glowStrength = 0.4 + (t * 0.5);
        return Transform.scale(
          scale: pulseScale * dragScale,
          child: Opacity(
            opacity: _dragging ? 0.88 : 1.0,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              elevation: 0,
              child: InkWell(
                onTap: _dragging ? null : widget.onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: _btnSize,
                  height: _btnSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(
                            _dragging ? 0.7 : glowStrength * 0.55),
                        blurRadius: _dragging ? 20 : 14 + (t * 10),
                        spreadRadius: _dragging ? 3 : t * 2,
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
          ),
        );
      },
    );

    // Uzun basip surukleme: buton ekranin istenen yerine tasinabilir.
    button = GestureDetector(
      onLongPressStart: (d) {
        HapticFeedback.mediumImpact();
        setState(() {
          _dragging = true;
          _dragPos = topLeft;
        });
      },
      onLongPressMoveUpdate: (d) {
        setState(() {
          final next = topLeft + d.offsetFromOrigin;
          _dragPos = Offset(
            next.dx.clamp(0.0, screen.width - _btnSize),
            next.dy.clamp(safe.top, screen.height - safe.bottom - _btnSize),
          );
        });
      },
      onLongPressEnd: (d) {
        final fx = (_dragPos!.dx / screen.width).clamp(0.0, 1.0);
        final fy = (_dragPos!.dy / screen.height).clamp(0.0, 1.0);
        LabelInspectButtonPrefs.instance.setPosition(fx, fy);
        HapticFeedback.selectionClick();
        setState(() {
          _dragging = false;
          _dragPos = null;
        });
      },
      child: button,
    );

    // Varsayilan (ozel konum tasinmamis) konumdayken nav bar ile senkron
    // asagi/yukari kayar; ozel konuma tasinmissa kullanicinin sectigi
    // yerde sabit kalir (beklenmedik kaymalar can sikici olur).
    if (!hasCustom && _dragPos == null) {
      button = ValueListenableBuilder<bool>(
        valueListenable: navBarVisible,
        builder: (_, navVisible, child) => AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          offset: navVisible ? Offset.zero : const Offset(0, 1.6),
          child: child,
        ),
        child: button,
      );
    }

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      child: button,
    );
  }
}
