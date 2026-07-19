import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  KONUM CANLANDIRMA — "Soft Glass" tasarım diliyle
/// ────────────────────────────────────────────────────────────────────
///  Uygulamanın kendi tema tokenlarını kullanan, sade bir "hedefe
///  yakınlaş" animasyonu: cam kart açılır, (varsa) reyon/depo şeridi
///  kısaca gösterilip hedefe geçilir, ızgara hedef hücreye doğru 2B
///  olarak (sahte 3B YOK) yakınlaşır, bir pin iner ve hücre yumuşakça
///  nabız atmaya başlar. Sahte perspektif/rotateX kullanılmıyor —
///  düz widget'larda bu her zaman çarpık görünür.
///
///  ORTAK SERVİSTİR: hem REYON hem DEPO konumları aynı fonksiyonla
///  canlandırılır.
///    showLocationFlythrough(context,
///      title: 'BAKLİYAT', cols: 5, rows: 6,
///      targetCol: 2, targetRow: 3,
///      subtitle: 'Sütun 2 · Raf 3', productName: ..., photoPath: ...);
/// ════════════════════════════════════════════════════════════════════
Future<void> showLocationFlythrough(
  BuildContext context, {
  required String title,
  required int cols,
  required int rows,
  required int targetCol, // 1-based
  required int targetRow, // 1-based (1 = EN ÜST raf)
  String? subtitle,
  String? productName,
  String? photoPath,
  Color? accent,
  /// Tüm reyon/depo isimleri. Birden fazlaysa, canlandırma önce kısa bir
  /// şerit gösterip hedefe geçer. Boş/tekil ise doğrudan ızgaradan başlar.
  List<String> allAisles = const [],
  int targetAisleIndex = 0,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
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
          allAisles: allAisles,
          targetAisleIndex: targetAisleIndex.clamp(
              0, allAisles.isEmpty ? 0 : allAisles.length - 1),
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
  final List<String> allAisles;
  final int targetAisleIndex;

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
    this.allAisles = const [],
    this.targetAisleIndex = 0,
  });

  @override
  State<_LocationRevealScreen> createState() => _LocationRevealScreenState();
}

class _LocationRevealScreenState extends State<_LocationRevealScreen>
    with TickerProviderStateMixin {
  late final AnimationController _main; // tek akış: kart -> (şerit) -> zoom -> pin
  late final AnimationController _pulse; // animasyon bitince yumuşak nabız

  bool get _hasAisles => widget.allAisles.length > 1;
  bool _photoExists = false;
  bool _landedHaptic = false;

  // ── Faz sınırları (0..1) — tek zaman çizgisi üzerinde ──
  double get _tCardIn => 0.14;
  double get _tAisleFadeStart => 0.06;
  double get _tAisleFadeEnd => 0.20;
  double get _tCrossStart => _hasAisles ? 0.32 : 0.0;
  double get _tCrossEnd => _hasAisles ? 0.46 : 0.0;
  double get _tGridStart => _hasAisles ? _tCrossStart : 0.12;
  double get _tGridEnd => _hasAisles ? _tCrossEnd : 0.28;
  double get _tZoomStart => _hasAisles ? 0.46 : 0.28;
  double get _tZoomEnd => _hasAisles ? 0.78 : 0.64;
  double get _tPinEnd => _hasAisles ? 0.90 : 0.84;
  double get _tInfoStart => _hasAisles ? 0.80 : 0.70;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _hasAisles ? 2400 : 1700),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _checkPhoto();
    _main.forward();
    _main.addListener(_checkLanding);
    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulse.repeat(reverse: true);
      }
    });

    HapticFeedback.selectionClick();
  }

  void _checkLanding() {
    if (!_landedHaptic && _main.value >= _tZoomEnd) {
      _landedHaptic = true;
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _checkPhoto() async {
    final path = widget.photoPath;
    if (path == null) return;
    try {
      final exists = await File(path).exists();
      if (mounted) setState(() => _photoExists = exists);
    } catch (_) {
      // sessizce yut — foto yoksa placeholder gösterilir
    }
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _replay() {
    _pulse.stop();
    _pulse.value = 0;
    _landedHaptic = false;
    _main.forward(from: 0);
    HapticFeedback.selectionClick();
  }

  void _dismiss() => Navigator.of(context).maybePop();

  double _seg(double t, double a, double b, [Curve c = Curves.easeInOut]) {
    if (a >= b) return t >= b ? 1.0 : 0.0;
    if (t <= a) return 0.0;
    if (t >= b) return 1.0;
    return c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accent;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Bulanık, yarı saydam zemin (dokununca kapanır) ──
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismiss,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  color: (AppTheme.isLight ? Colors.black : Colors.black)
                      .withOpacity(AppTheme.isLight ? 0.22 : 0.55),
                ),
              ),
            ),
          ),

          // ── Kart ──
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_main, _pulse]),
                builder: (context, _) {
                  final t = _main.value;
                  final pulse = _pulse.value;

                  final cardIn = _seg(t, 0.0, _tCardIn, Curves.easeOutCubic);
                  final aisleIn =
                      _hasAisles ? _seg(t, _tAisleFadeStart, _tAisleFadeEnd) : 0.0;
                  final cross =
                      _hasAisles ? _seg(t, _tCrossStart, _tCrossEnd) : 1.0;
                  final aisleOpacity =
                      _hasAisles ? (aisleIn * (1 - cross)).clamp(0.0, 1.0) : 0.0;
                  final gridOpacity = _hasAisles
                      ? cross.clamp(0.0, 1.0)
                      : _seg(t, _tGridStart, _tGridEnd, Curves.easeOutCubic);
                  final zoom = _seg(
                      t, _tZoomStart, _tZoomEnd, Curves.easeInOutCubic);
                  final pinDrop =
                      _seg(t, _tZoomEnd, _tPinEnd, Curves.easeOutBack);
                  final infoIn =
                      _seg(t, _tInfoStart, 1.0, Curves.easeOutCubic);

                  return Opacity(
                    opacity: cardIn,
                    child: Transform.scale(
                      scale: 0.92 + 0.08 * cardIn,
                      child: GestureDetector(
                        onTap: () {}, // kartın üstüne dokununca kapanmasın
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: GlassPanel(
                              radius: AppTheme.rXl,
                              elevated: true,
                              accentColor: acc,
                              padding: const EdgeInsets.all(AppTheme.s20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _header(acc),
                                  const SizedBox(height: AppTheme.s16),
                                  SizedBox(
                                    height: 200,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (_hasAisles)
                                          Positioned.fill(
                                            child: Opacity(
                                              opacity: aisleOpacity,
                                              child: _aisleStrip(acc, pulse),
                                            ),
                                          ),
                                        Positioned.fill(
                                          child: Opacity(
                                            opacity: gridOpacity,
                                            child: _gridViewport(
                                                acc, zoom, pinDrop, pulse),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.productName != null ||
                                      widget.photoPath != null) ...[
                                    const SizedBox(height: AppTheme.s16),
                                    Opacity(
                                      opacity: infoIn,
                                      child: Transform.translate(
                                        offset: Offset(0, (1 - infoIn) * 8),
                                        child: _infoRow(),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: AppTheme.s20),
                                  _buttons(acc),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  BAŞLIK
  // ════════════════════════════════════════════════════════════════════
  Widget _header(Color acc) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: acc.withOpacity(0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.pin_drop_rounded, color: acc, size: 20),
        ),
        const SizedBox(width: AppTheme.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: acc,
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: _dismiss,
          icon: Icon(Icons.close_rounded, color: AppTheme.textTertiary, size: 20),
          splashRadius: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  REYON/DEPO ŞERİDİ (birden fazla reyon varsa kısa bir ön izleme)
  // ════════════════════════════════════════════════════════════════════
  Widget _aisleStrip(Color acc, double pulse) {
    final aisles = widget.allAisles;
    return Center(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: List.generate(aisles.length, (i) {
          final isTarget = i == widget.targetAisleIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: isTarget
                ? BoxDecoration(
                    color: acc.withOpacity(0.16 + 0.06 * pulse),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                    border: Border.all(color: acc, width: 1.4),
                  )
                : AppTheme.softTint(AppTheme.textTertiary,
                    radius: AppTheme.rPill),
            child: Text(
              aisles[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: isTarget ? FontWeight.w800 : FontWeight.w500,
                color: isTarget ? acc : AppTheme.textSecondary,
              ),
            ),
          );
        }),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  IZGARA — hedef hücreye 2B (sahte-3B YOK) yakınlaşma
  // ════════════════════════════════════════════════════════════════════
  Widget _gridViewport(Color acc, double zoom, double pinDrop, double pulse) {
    final ax = widget.cols == 1
        ? 0.0
        : ((widget.targetCol - 0.5) / widget.cols) * 2 - 1;
    final ay = widget.rows == 1
        ? 0.0
        : ((widget.targetRow - 0.5) / widget.rows) * 2 - 1;
    final scale = 1.0 + zoom * 1.1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Container(
        color: AppTheme.surfaceAlt,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 5.0;
            final cellSize = ((constraints.maxWidth - gap * (widget.cols + 1)) /
                    widget.cols)
                .clamp(10.0, 30.0);
            final gridW = cellSize * widget.cols + gap * (widget.cols + 1);
            final gridH = cellSize * widget.rows + gap * (widget.rows + 1);
            final targetLeft =
                gap + (widget.targetCol - 1) * (cellSize + gap);
            final targetTop = gap + (widget.targetRow - 1) * (cellSize + gap);

            return Transform(
              alignment: Alignment(ax, ay),
              transform: Matrix4.identity()..scale(scale),
              child: Center(
                child: SizedBox(
                  width: gridW,
                  height: gridH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var r = 0; r < widget.rows; r++)
                        for (var c = 0; c < widget.cols; c++)
                          _cell(c, r, cellSize, gap, acc, zoom, pinDrop),

                      // ── Konum pini — hedef hücrenin tam üstüne iner ──
                      Positioned(
                        left: targetLeft + cellSize / 2 - 11,
                        top: targetTop - 24 - (1 - pinDrop) * 34,
                        child: Opacity(
                          opacity: pinDrop.clamp(0.0, 1.0),
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 22 + 3 * pulse,
                            color: acc,
                            shadows: [
                              Shadow(
                                  color: acc.withOpacity(0.45), blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _cell(int c, int r, double cellSize, double gap, Color acc,
      double zoom, double pinDrop) {
    final isTarget = (c + 1) == widget.targetCol && (r + 1) == widget.targetRow;
    final dim = isTarget ? 1.0 : (1.0 - zoom * 0.6).clamp(0.35, 1.0);

    return Positioned(
      left: gap + c * (cellSize + gap),
      top: gap + r * (cellSize + gap),
      width: cellSize,
      height: cellSize,
      child: Opacity(
        opacity: dim,
        child: Container(
          decoration: BoxDecoration(
            color: isTarget ? acc : AppTheme.hairline,
            borderRadius: BorderRadius.circular(cellSize * 0.3),
            border: isTarget
                ? Border.all(color: Colors.white.withOpacity(0.85), width: 1.4)
                : null,
            boxShadow: isTarget ? AppTheme.glow(acc) : null,
          ),
          child: isTarget && pinDrop > 0.55
              ? Center(
                  child: Icon(
                    Icons.check_rounded,
                    size: cellSize * 0.6,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  ÜRÜN BİLGİSİ + BUTONLAR
  // ════════════════════════════════════════════════════════════════════
  Widget _infoRow() {
    final showPhoto = widget.photoPath != null && _photoExists;
    return Row(
      children: [
        if (showPhoto)
          Container(
            width: 52,
            height: 52,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              border: Border.all(color: AppTheme.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(widget.photoPath!),
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) =>
                  Container(color: AppTheme.surfaceAlt),
            ),
          ),
        if (widget.productName != null)
          Expanded(
            child: Text(
              widget.productName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buttons(Color acc) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _replay,
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Tekrar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: BorderSide(color: AppTheme.hairline),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTheme.s12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _dismiss,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Tamam'),
            style: FilledButton.styleFrom(
              backgroundColor: acc,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
