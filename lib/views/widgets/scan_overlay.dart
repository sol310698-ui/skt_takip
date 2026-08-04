import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// ══════════════════════════════════════════════════════════════════════
///  ORTAK TARAMA ARAYUZU (ScanOverlay)
/// ──────────────────────────────────────────────────────────────────────
///  Tum barkod okuma ekranlarinda AYNI gorunumu saglayan katman. Kameranin
///  USTUNE bindirilir; kamera/okuma mantigina dokunmaz, sadece gorunum.
///
///  Tasarim: modern koyu. Karartilmis kamera + ortada yuvarlak koseli
///  tarama penceresi + hareketli tarama cizgisi + kose vurgulari + altta
///  ipucu metni. Marka rengi (mavi) vurgu olarak kullanilir.
///
///  Kullanim: MobileScanner'in ustune Stack icinde koy:
///    Stack(children: [ MobileScanner(...), const ScanOverlay(hint: '...') ])
/// ══════════════════════════════════════════════════════════════════════
class ScanOverlay extends StatefulWidget {
  /// Tarama penceresinin altinda gosterilen ipucu ( or. "Barkodu okutun").
  final String hint;

  /// Vurgu rengi (verilmezse aktif marka rengi). Uyari/eslesme durumunda
  /// degistirilebilir (ornegin bulunamayinca turuncu).
  /// NOT: null birakilir; build sirasinda AppTheme.primary'e cozulur. Boylece
  /// const constructor korunur ama vurgu rengi degistirilebilir kalir.
  final Color? accent;

  /// Tarama penceresi boyutu (kare kenar orani ekran genisligine gore).
  final double windowWidthFactor;

  /// Pencere en-boy orani (genislik/yukseklik). Barkodlar yatay oldugu icin
  /// varsayilan genis dikdortgen.
  final double aspect;

  /// Ust bilgi (ekran basligi gibi) — istege bagli.
  final String? title;

  const ScanOverlay({
    super.key,
    this.hint = 'Barkodu çerçeveye getirin',
    this.accent,
    this.windowWidthFactor = 0.78,
    this.aspect = 1.7,
    this.title,
  });

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  // Cizgi kenarlara (yukari/asagi) yaklasirken yavaslayip hizlansin diye
  // ham controller degeri yerine bunu kullaniyoruz. Duz (linear) deger,
  // cizginin pencere kenarlarinda sert bir sekilde "ziplamasina" yol
  // aciyordu; gercek bir tarayici/lazer gibi yumusak gorunmesi icin
  // easeInOut egrisi kullaniyoruz (bkz. flutter.dev CurvedAnimation).
  late final Animation<double> _lineAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _lineAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Vurgu rengi verilmediyse aktif marka rengine coz.
        final acc = widget.accent ?? AppTheme.primary;
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final winW = w * widget.windowWidthFactor;
        final winH = winW / widget.aspect;
        final left = (w - winW) / 2;
        final top = (h - winH) / 2;

        return Stack(
          children: [
            // ── Karartma katmani (pencere disini karart) ──
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.6),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    child: Container(
                      width: winW,
                      height: winH,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Tarama penceresi cercevesi + kose vurgulari ──
            Positioned(
              left: left,
              top: top,
              child: SizedBox(
                width: winW,
                height: winH,
                child: CustomPaint(
                  painter: _CornerPainter(color: acc),
                ),
              ),
            ),

            // ── Hareketli tarama cizgisi ──
            Positioned(
              left: left,
              top: top,
              child: SizedBox(
                width: winW,
                height: winH,
                child: AnimatedBuilder(
                  animation: _lineAnim,
                  builder: (context, _) {
                    return Align(
                      alignment: Alignment(0, (_lineAnim.value * 2) - 1),
                      child: Container(
                        height: 2.5,
                        width: winW - 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              acc.withOpacity(0),
                              acc,
                              acc.withOpacity(0),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: acc.withOpacity(0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Alt ipucu metni ──
            Positioned(
              left: 24,
              right: 24,
              top: top + winH + 28,
              child: Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            ),

            // ── Ust baslik (istege bagli) ──
            if (widget.title != null)
              Positioned(
                left: 24,
                right: 24,
                top: top - 44,
                child: Text(
                  widget.title!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                    shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tarama penceresinin dort kosesine L-seklinde vurgu cizer.
class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const cornerLen = 26.0;
    const r = 20.0; // kose yaricapi

    // Sol ust
    canvas.drawPath(
      Path()
        ..moveTo(0, r + cornerLen)
        ..lineTo(0, r)
        ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
        ..lineTo(r + cornerLen, 0),
      paint,
    );
    // Sag ust
    canvas.drawPath(
      Path()
        ..moveTo(size.width - r - cornerLen, 0)
        ..lineTo(size.width - r, 0)
        ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
        ..lineTo(size.width, r + cornerLen),
      paint,
    );
    // Sol alt
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - r - cornerLen)
        ..lineTo(0, size.height - r)
        ..arcToPoint(Offset(r, size.height),
            radius: const Radius.circular(r), clockwise: false)
        ..lineTo(r + cornerLen, size.height),
      paint,
    );
    // Sag alt
    canvas.drawPath(
      Path()
        ..moveTo(size.width - r - cornerLen, size.height)
        ..lineTo(size.width - r, size.height)
        ..arcToPoint(Offset(size.width, size.height - r),
            radius: const Radius.circular(r), clockwise: false)
        ..lineTo(size.width, size.height - r - cornerLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) =>
      oldDelegate.color != color;
}
