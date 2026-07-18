import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  KONUM CANLANDIRMA — "KAMERA INISI" (cinematic fly-to)
/// ────────────────────────────────────────────────────────────────────
///  Google Haritalar'in bir noktaya "ucarak inmesi" gibi: once mekanin
///  adi DEV harflerle belirir, ardindan raf/depo izgarasina TEPEDEN bakan
///  kamera, hedef hucreye dogru suzulerek YAKINLASIR (olcek + perspektif
///  egimi ayni anda degisir — oyun kamerasi hissi). Inis bitince hedefe
///  yukaridan bir konum pini duser, ziplar ve nabiz atmaya baslar.
///
///  ORTAK SERVISTIR: hem REYON (etiket tarama) hem DEPO (palet) konumlari
///  ayni fonksiyonla canlandirilir:
///    showLocationReveal(context,
///      title: 'BAKLİYAT', cols: 5, rows: 6,
///      targetCol: 2, targetRow: 3,
///      subtitle: 'Sütun 2 · Raf 3', productName: ..., photoPath: ...);
/// ════════════════════════════════════════════════════════════════════
Future<void> showLocationReveal(
  BuildContext context, {
  required String title,
  required int cols,
  required int rows,
  required int targetCol, // 1-based
  required int targetRow, // 1-based (1 = EN UST raf)
  String? subtitle,
  String? productName,
  String? photoPath,
  Color? accent,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _LocationRevealScreen(
          title: title,
          cols: cols.clamp(1, 30),
          rows: rows.clamp(1, 30),
          targetCol: targetCol.clamp(1, cols.clamp(1, 30)),
          targetRow: targetRow.clamp(1, rows.clamp(1, 30)),
          subtitle: subtitle,
          productName: productName,
          photoPath: photoPath,
          accent: accent ?? AppTheme.accent,
        ),
      ),
    ),
  );
}

class _LocationRevealScreen extends StatefulWidget {
  final String title;
  final int cols, rows, targetCol, targetRow;
  final String? subtitle, productName, photoPath;
  final Color accent;
  const _LocationRevealScreen({
    required this.title,
    required this.cols,
    required this.rows,
    required this.targetCol,
    required this.targetRow,
    required this.accent,
    this.subtitle,
    this.productName,
    this.photoPath,
  });

  @override
  State<_LocationRevealScreen> createState() => _LocationRevealScreenState();
}

class _LocationRevealScreenState extends State<_LocationRevealScreen>
    with TickerProviderStateMixin {
  // Ana zaman cizelgesi (~3.4 sn): baslik -> izgara -> inis -> pin.
  late final AnimationController _main = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3400));
  // Pin nabzi (inis bittikten sonra surekli).
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));

  // Faz araliklari (0..1)
  static const _tTitleIn = 0.12; // baslik belirir
  static const _tGridIn = 0.30; // izgara uzaktan gorunur
  static const _tFlyEnd = 0.80; // kamera inisi biter
  static const _tPinEnd = 0.95; // pin duser + ziplar

  @override
  void initState() {
    super.initState();
    _main.forward();
    _main.addStatusListener((st) {
      if (st == AnimationStatus.completed) _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _replay() {
    _pulse.stop();
    _main.forward(from: 0);
  }

  double _seg(double t, double a, double b, [Curve c = Curves.easeInOut]) {
    if (t <= a) return 0;
    if (t >= b) return 1;
    return c.transform((t - a) / (b - a));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accent;
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_main, _pulse]),
            builder: (context, _) {
              final t = _main.value;

              // ── FAZ DEGERLERI ──
              final titleIn = _seg(t, 0.0, _tTitleIn, Curves.easeOutBack);
              // Baslik, inis baslarken yukari cekilip kuculur.
              final titleUp = _seg(t, _tGridIn, _tFlyEnd);
              final gridIn = _seg(t, _tTitleIn, _tGridIn);
              final fly = _seg(t, _tGridIn, _tFlyEnd, Curves.easeInOutCubic);
              final pinDrop = _seg(t, _tFlyEnd, _tPinEnd, Curves.bounceOut);

              // Kamera: uzak tepeden (kucuk + egik) -> yakin onden (buyuk, duz)
              final scale = 0.72 + fly * 1.9; // 0.72 -> 2.62
              final tilt = (1 - fly) * 0.85; // radyan: tepeden bakis egimi
              // Hedef hucrenin izgara icindeki goreli konumu (-1..1):
              final ax = widget.cols == 1
                  ? 0.0
                  : ((widget.targetCol - 0.5) / widget.cols) * 2 - 1;
              final ay = widget.rows == 1
                  ? 0.0
                  : ((widget.targetRow - 0.5) / widget.rows) * 2 - 1;

              return Column(
                children: [
                  const SizedBox(height: 18),
                  // ── DEV BASLIK ──
                  Transform.scale(
                    scale: (0.6 + 0.4 * titleIn) * (1 - 0.45 * titleUp),
                    child: Opacity(
                      opacity: titleIn,
                      child: Column(
                        children: [
                          Text(
                            widget.title.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(color: acc, blurRadius: 24),
                              ],
                            ),
                          ),
                          if (widget.subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                widget.subtitle!,
                                style: TextStyle(
                                  color: acc,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── IZGARA + KAMERA ──
                  Expanded(
                    child: ClipRect(
                      child: Opacity(
                        opacity: gridIn,
                        child: Transform(
                          alignment: Alignment(ax, ay),
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012) // perspektif
                            ..rotateX(tilt)
                            ..scale(scale),
                          child: Center(
                            child: _grid(acc, pinDrop),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── ALT BILGI + BUTONLAR ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: Column(
                      children: [
                        if (widget.productName != null)
                          Text(
                            widget.productName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _replay,
                                icon: const Icon(Icons.replay_rounded,
                                    size: 20),
                                label: const Text('Tekrar oynat'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white38),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                icon: const Icon(Icons.check_rounded,
                                    size: 20),
                                label: const Text('Tamam'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: acc,
                                    foregroundColor: Colors.black),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Reyon/depo izgarasi: satirlar = raflar (ustte 1), her satirin altinda
  /// raf tahtasi cizgisi; hedef hucre parlak + (inis sonrasi) pinli.
  Widget _grid(Color acc, double pinDrop) {
    const cellW = 44.0, cellH = 40.0, gap = 5.0;
    final w = widget.cols * (cellW + gap) + gap;

    return SizedBox(
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.rows, (r) {
          final rowNo = r + 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(widget.cols, (c) {
                    final colNo = c + 1;
                    final isTarget = colNo == widget.targetCol &&
                        rowNo == widget.targetRow;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: gap / 2),
                      child: _cellBox(isTarget, acc, pinDrop),
                    );
                  }),
                ),
                const SizedBox(height: 2),
                // Raf tahtasi.
                Container(
                  width: w - gap,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _cellBox(bool isTarget, Color acc, double pinDrop) {
    const cellW = 44.0, cellH = 40.0;
    final pulse = isTarget ? (0.9 + 0.2 * _pulse.value) : 1.0;

    final hasPhoto = isTarget &&
        widget.photoPath != null &&
        File(widget.photoPath!).existsSync();

    return SizedBox(
      width: cellW,
      height: cellH + 18, // pin icin ust bosluk
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Hucre kutusu.
          Container(
            width: cellW,
            height: cellH,
            decoration: BoxDecoration(
              color: isTarget
                  ? acc.withOpacity(0.9)
                  : Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isTarget ? Colors.white : Colors.white24,
                width: isTarget ? 1.6 : 0.8,
              ),
              boxShadow: isTarget
                  ? [
                      BoxShadow(
                        color: acc.withOpacity(0.5 * _pulse.value + 0.3),
                        blurRadius: 16 * pulse,
                        spreadRadius: 2 * _pulse.value,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? Image.file(File(widget.photoPath!), fit: BoxFit.cover)
                : null,
          ),
          // Konum pini: yukaridan duser (bounce), sonra nabizla birlikte
          // hafifce yukari-asagi salinir.
          if (isTarget && pinDrop > 0)
            Positioned(
              top: -26 + (1 - pinDrop) * -40 - _pulse.value * 3,
              child: Opacity(
                opacity: pinDrop.clamp(0, 1),
                child: Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 30,
                  shadows: [Shadow(color: acc, blurRadius: 14)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
