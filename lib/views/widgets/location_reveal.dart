import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Reyon canlandırmasının "raf" fazında gösterilecek tek bir ürün.
/// Hedef rafta (row_no) soldan sağa dizili ürünlerden biri.
class RevealShelfProduct {
  final String? name;
  final String? photoPath;
  final int? sectionNo; // hangi sütunda (bilgi amaçlı)
  final bool isTarget; // aranan ürün mü?
  const RevealShelfProduct({
    this.name,
    this.photoPath,
    this.sectionNo,
    this.isTarget = false,
  });
}

/// ════════════════════════════════════════════════════════════════════
///  KONUM CANLANDIRMA — "Reyon Haritası → Rafa Yakınlaş"
/// ────────────────────────────────────────────────────────────────────
///  AMAÇ: Çalışanın ürünü GERÇEKTEN bulması. İki aşama:
///
///   1) HARİTA — sabit, okunur reyon ızgarası. Sütun/raf numaraları
///      kenarda; hedef sütun+raf çapraz aydınlatılır, kesişim (hedef
///      hücre) vurgulanır, pin iner. Göz "Sütun 2 · Raf 3"ü bir bakışta
///      okur. Yanıltıcı perspektif/zoom YOK.
///
///   2) RAF — harita hafifçe içeri büyüyüp solar; yerine o raftaki
///      ürünlerin FOTOĞRAF ŞERİDİ gelir (gerçek soldan-sağa dizilim).
///      ARANAN ürün büyük, çerçeveli, rozetli ve nabız atar; komşular
///      sönük. Böylece rafın önünde ürünü gözle hemen eşler.
///      (shelfProducts boşsa bu aşama atlanır; eski davranış korunur.)
///
///  ORTAK API — imza geriye dönük uyumlu; yeni parametre opsiyonel.
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
  /// Tüm reyon/depo isimleri. Birden fazlaysa hedef reyon çip şeridiyle
  /// vurgulanır (önce doğru reyona git, sonra hücreyi bul).
  List<String> allAisles = const [],
  int targetAisleIndex = 0,
  /// Hedef raftaki (row_no) ürünler, soldan sağa. Doluysa "rafa yakınlaş"
  /// aşaması oynatılır ve aranan ürün (isTarget) belirginleştirilir.
  List<RevealShelfProduct> shelfProducts = const [],
}) {
  final safeCols = cols.clamp(1, 30);
  final safeRows = rows.clamp(1, 30);
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
          cols: safeCols,
          rows: safeRows,
          targetCol: targetCol.clamp(1, safeCols),
          targetRow: targetRow.clamp(1, safeRows),
          subtitle: subtitle,
          productName: productName,
          photoPath: photoPath,
          accent: accent ?? AppTheme.accent,
          allAisles: allAisles,
          targetAisleIndex: targetAisleIndex.clamp(
              0, allAisles.isEmpty ? 0 : allAisles.length - 1),
          shelfProducts: shelfProducts,
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
  final List<RevealShelfProduct> shelfProducts;

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
    this.shelfProducts = const [],
  });

  @override
  State<_LocationRevealScreen> createState() => _LocationRevealScreenState();
}

class _LocationRevealScreenState extends State<_LocationRevealScreen>
    with TickerProviderStateMixin {
  late final AnimationController _main; // kart -> harita -> pin -> raf
  late final AnimationController _pulse; // bitince yumuşak nabız
  final ScrollController _stripCtrl = ScrollController();
  bool _stripCentered = false;

  bool get _hasAisles => widget.allAisles.length > 1;
  bool get _hasShelf => widget.shelfProducts.isNotEmpty;
  bool _photoExists = false;
  bool _landedHaptic = false;
  bool _shelfHaptic = false;

  // ── Raf şeridi ölçüleri (px) ──
  static const double _kGap = 12;
  static const double _kNonTargetW = 76;
  static const double _kTargetW = 108;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _hasShelf ? 2600 : 1400),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _checkPhoto();
    _main.forward();
    _main.addListener(_checkHaptics);
    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) _pulse.repeat(reverse: true);
    });

    HapticFeedback.selectionClick();
  }

  void _checkHaptics() {
    if (!_landedHaptic && _main.value >= (_hasShelf ? 0.56 : 0.78)) {
      _landedHaptic = true;
      HapticFeedback.mediumImpact();
    }
    if (_hasShelf && !_shelfHaptic && _main.value >= 0.86) {
      _shelfHaptic = true;
      HapticFeedback.selectionClick();
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
    _stripCtrl.dispose();
    super.dispose();
  }

  void _replay() {
    _pulse.stop();
    _pulse.value = 0;
    _landedHaptic = false;
    _shelfHaptic = false;
    _stripCentered = false;
    if (_stripCtrl.hasClients) _stripCtrl.jumpTo(0);
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
                  color:
                      Colors.black.withOpacity(AppTheme.isLight ? 0.22 : 0.55),
                ),
              ),
            ),
          ),

          // ── Kart (dikeyde ortalı; sığmazsa kaydırılır) ──
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: viewport.maxHeight - 48),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_main, _pulse]),
                      builder: (context, _) {
                        final t = _main.value;
                        final pulse = _pulse.value;

                        final cardIn =
                            _seg(t, 0.0, 0.12, Curves.easeOutCubic);
                        final chipsIn =
                            _hasAisles ? _seg(t, 0.06, 0.22) : 0.0;
                        final bannerIn =
                            _seg(t, 0.03, 0.18, Curves.easeOutCubic);
                        // "Rafa yakınlaş": harita -> raf şeridi geçişi.
                        final shelfReveal = _hasShelf
                            ? _seg(t, 0.60, 0.90, Curves.easeInOutCubic)
                            : 0.0;
                        final infoIn = _hasShelf
                            ? 0.0
                            : _seg(t, 0.72, 1.0, Curves.easeOutCubic);

                        return Opacity(
                          opacity: cardIn,
                          child: Transform.scale(
                            scale: 0.94 + 0.06 * cardIn,
                            child: GestureDetector(
                              onTap: () {}, // karta dokununca kapanmasın
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 400),
                                child: GlassPanel(
                                  radius: AppTheme.rXl,
                                  elevated: true,
                                  accentColor: acc,
                                  padding: const EdgeInsets.all(AppTheme.s20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _header(acc),
                                      const SizedBox(height: AppTheme.s16),

                                      // ── Büyük konum bandı ──
                                      Opacity(
                                        opacity: bannerIn,
                                        child: _locationBanner(acc),
                                      ),

                                      // ── Hangi reyon? ──
                                      if (_hasAisles) ...[
                                        const SizedBox(height: AppTheme.s12),
                                        Opacity(
                                          opacity: chipsIn,
                                          child: _aisleChips(acc, pulse),
                                        ),
                                      ],

                                      const SizedBox(height: AppTheme.s16),

                                      // ── SAHNE: harita ↔ raf şeridi ──
                                      if (_hasShelf)
                                        _stage(acc, t, shelfReveal, pulse)
                                      else
                                        _reyonMap(acc, t, pulse),

                                      // ── (raf yoksa) tekil ürün bilgisi ──
                                      if (!_hasShelf &&
                                          (widget.productName != null ||
                                              (widget.photoPath != null &&
                                                  _photoExists))) ...[
                                        const SizedBox(height: AppTheme.s16),
                                        Opacity(
                                          opacity: infoIn,
                                          child: Transform.translate(
                                            offset:
                                                Offset(0, (1 - infoIn) * 8),
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
                        );
                      },
                    ),
                  ),
                ),
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
                'REYON',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppTheme.textTertiary,
                ),
              ),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _dismiss,
          icon:
              Icon(Icons.close_rounded, color: AppTheme.textTertiary, size: 20),
          splashRadius: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  KONUM BANDI — büyük "Sütun X · Raf Y"
  // ════════════════════════════════════════════════════════════════════
  Widget _locationBanner(Color acc) {
    Widget chip(String label, String value) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 30,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: acc,
                letterSpacing: -0.5,
              ),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: acc.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: acc.withOpacity(0.35), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          chip('SÜTUN', '${widget.targetCol}'),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 22),
            color: acc.withOpacity(0.25),
          ),
          chip('RAF', '${widget.targetRow}'),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  REYON ÇİPLERİ
  // ════════════════════════════════════════════════════════════════════
  Widget _aisleChips(Color acc, double pulse) {
    final aisles = widget.allAisles;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: List.generate(aisles.length, (i) {
        final isTarget = i == widget.targetAisleIndex;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
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
              fontSize: 12.5,
              fontWeight: isTarget ? FontWeight.w800 : FontWeight.w500,
              color: isTarget ? acc : AppTheme.textSecondary,
            ),
          ),
        );
      }),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  SAHNE — harita ile raf şeridini çapraz geçişle bir arada tutar.
  //  shelfReveal: 0 = tam harita · 1 = tam raf şeridi ("yakınlaşma").
  // ════════════════════════════════════════════════════════════════════
  Widget _stage(Color acc, double t, double shelfReveal, double pulse) {
    const stageH = 240.0;
    final mapOpacity = (1 - shelfReveal).clamp(0.0, 1.0);
    final mapScale = 1.0 + shelfReveal * 0.14; // içeri "uçma" hissi
    final stripOpacity = shelfReveal;
    final stripScale = 0.92 + 0.08 * shelfReveal;

    return SizedBox(
      height: stageH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Harita (altta) — yakınlaşırken büyüyüp solar
          IgnorePointer(
            ignoring: shelfReveal > 0.5,
            child: Opacity(
              opacity: mapOpacity,
              child: Transform.scale(
                scale: mapScale,
                child: _reyonMap(acc, t, pulse),
              ),
            ),
          ),
          // Raf şeridi (üstte) — belirir
          if (shelfReveal > 0.001)
            IgnorePointer(
              ignoring: shelfReveal < 0.5,
              child: Opacity(
                opacity: stripOpacity,
                child: Transform.scale(
                  scale: stripScale,
                  child: _shelfStrip(acc, shelfReveal, pulse),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  REYON HARİTASI — sabit, koordinat-vurgulu ızgara
  // ════════════════════════════════════════════════════════════════════
  Widget _reyonMap(Color acc, double t, double pulse) {
    const gutter = 26.0;
    const topLabel = 24.0;
    const gap = 6.0;

    return Container(
      padding: const EdgeInsets.all(AppTheme.s12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availW = constraints.maxWidth;
          final availH =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0;
          final cellByW =
              (availW - gutter - gap * (widget.cols + 1)) / widget.cols;
          final cellByH =
              (availH - topLabel - gap * (widget.rows + 1)) / widget.rows;
          final cell = cellByW < cellByH ? cellByW : cellByH;
          final cellSize = cell.clamp(12.0, 46.0);

          final gridW =
              gutter + gap * (widget.cols + 1) + cellSize * widget.cols;
          final gridH =
              topLabel + gap * (widget.rows + 1) + cellSize * widget.rows;

          final pinDrop = _seg(t, 0.42, 0.60, Curves.easeOutBack);
          final targetPop = _seg(t, 0.30, 0.48, Curves.easeOutBack);
          final targetLeft =
              gutter + gap + (widget.targetCol - 1) * (cellSize + gap);
          final targetTop =
              topLabel + gap + (widget.targetRow - 1) * (cellSize + gap);

          return Center(
            child: SizedBox(
              width: gridW,
              height: gridH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var c = 0; c < widget.cols; c++)
                    Positioned(
                      left: gutter + gap + c * (cellSize + gap),
                      top: 0,
                      width: cellSize,
                      height: topLabel,
                      child: _axisLabel('${c + 1}',
                          highlight: (c + 1) == widget.targetCol, acc: acc),
                    ),
                  for (var r = 0; r < widget.rows; r++)
                    Positioned(
                      left: 0,
                      top: topLabel + gap + r * (cellSize + gap),
                      width: gutter,
                      height: cellSize,
                      child: _axisLabel('${r + 1}',
                          highlight: (r + 1) == widget.targetRow, acc: acc),
                    ),
                  for (var r = 0; r < widget.rows; r++)
                    for (var c = 0; c < widget.cols; c++)
                      _cell(c, r, cellSize, gap, gutter, topLabel, acc, t,
                          targetPop, pinDrop, pulse),
                  Positioned(
                    left: targetLeft + cellSize / 2 - 11,
                    top: targetTop - 22 - (1 - pinDrop) * 30,
                    child: Opacity(
                      opacity: pinDrop.clamp(0.0, 1.0),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 22 + 3 * pulse,
                        color: acc,
                        shadows: [
                          Shadow(color: acc.withOpacity(0.45), blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _axisLabel(String text,
      {required bool highlight, required Color acc}) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: highlight ? 14 : 12,
          fontWeight: highlight ? FontWeight.w900 : FontWeight.w600,
          color: highlight ? acc : AppTheme.textTertiary,
        ),
      ),
    );
  }

  Widget _cell(int c, int r, double cellSize, double gap, double gutter,
      double topLabel, Color acc, double t, double targetPop, double pinDrop,
      double pulse) {
    final isTarget =
        (c + 1) == widget.targetCol && (r + 1) == widget.targetRow;
    final sameCol = (c + 1) == widget.targetCol;
    final sameRow = (r + 1) == widget.targetRow;

    final rowFrac = widget.rows <= 1 ? 0.0 : r / widget.rows;
    final appear =
        _seg(t, 0.10 + rowFrac * 0.16, 0.32 + rowFrac * 0.16, Curves.easeOut);

    Color fill;
    BoxBorder? border;
    List<BoxShadow>? shadow;
    if (isTarget) {
      fill = acc;
      border = Border.all(color: Colors.white.withOpacity(0.9), width: 1.6);
      shadow = AppTheme.glow(acc);
    } else if (sameCol || sameRow) {
      fill = acc.withOpacity(0.16);
      border = Border.all(color: acc.withOpacity(0.30), width: 1);
    } else {
      fill = AppTheme.hairline;
    }

    final scale = isTarget ? (0.6 + 0.4 * targetPop) : 1.0;

    return Positioned(
      left: gutter + gap + c * (cellSize + gap),
      top: topLabel + gap + r * (cellSize + gap),
      width: cellSize,
      height: cellSize,
      child: Opacity(
        opacity: appear,
        child: Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(cellSize * 0.28),
              border: border,
              boxShadow: shadow,
            ),
            child: isTarget && pinDrop > 0.55
                ? Center(
                    child: Icon(Icons.check_rounded,
                        size: cellSize * 0.6, color: Colors.white),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  RAF ŞERİDİ — raftaki ürünlerin fotoğrafları, aranan belirgin
  // ════════════════════════════════════════════════════════════════════
  Widget _shelfStrip(Color acc, double reveal, double pulse) {
    final products = widget.shelfProducts;
    final targetIndex = products.indexWhere((p) => p.isTarget);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 14, right: 14),
            child: Row(
              children: [
                Icon(Icons.view_week_rounded,
                    size: 15, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(
                  'Raf ${widget.targetRow} · bu raftaki ürünler',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final vw = cons.maxWidth;
                // Aranan ürünü ortala (şerit taşarsa kaydır).
                if (!_stripCentered && targetIndex >= 0) {
                  double x = 14; // sol iç boşluk
                  double targetCenter = x;
                  for (var i = 0; i < products.length; i++) {
                    final w =
                        products[i].isTarget ? _kTargetW : _kNonTargetW;
                    if (i == targetIndex) targetCenter = x + w / 2;
                    x += w + _kGap;
                  }
                  final off = targetCenter - vw / 2;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_stripCentered && _stripCtrl.hasClients) {
                      final max = _stripCtrl.position.maxScrollExtent;
                      _stripCtrl.jumpTo(off.clamp(0.0, max));
                      _stripCentered = true;
                    }
                  });
                }
                return SingleChildScrollView(
                  controller: _stripCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < products.length; i++) ...[
                        if (i > 0) const SizedBox(width: _kGap),
                        _shelfTile(products[i], acc, pulse),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _shelfTile(RevealShelfProduct p, Color acc, double pulse) {
    final isT = p.isTarget;
    final w = isT ? _kTargetW : _kNonTargetW;
    final photo = isT ? _kTargetW : _kNonTargetW;
    final scale = isT ? (1.0 + 0.03 * pulse) : 1.0;

    return Opacity(
      opacity: isT ? 1.0 : 0.6,
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: photo,
                    height: photo,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                      border: isT
                          ? Border.all(color: acc, width: 2.4)
                          : Border.all(color: AppTheme.hairline),
                      boxShadow: isT ? AppTheme.glow(acc) : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _photo(p.photoPath),
                  ),
                  if (isT)
                    Positioned(
                      top: -8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: acc,
                            borderRadius:
                                BorderRadius.circular(AppTheme.rPill),
                            boxShadow: AppTheme.glow(acc),
                          ),
                          child: const Text(
                            'ARANAN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              if (p.name != null)
                Text(
                  p.name!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isT ? 12.5 : 11.5,
                    height: 1.2,
                    fontWeight: isT ? FontWeight.w800 : FontWeight.w500,
                    color: isT ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              if (p.sectionNo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Sütun ${p.sectionNo}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isT ? acc : AppTheme.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo(String? path) {
    if (path == null) return _photoPlaceholder();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (ctx, err, stack) => _photoPlaceholder(),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: AppTheme.surface,
      child: Icon(Icons.inventory_2_rounded,
          color: AppTheme.textTertiary, size: 26),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  TEKİL ÜRÜN BİLGİSİ (raf verisi yoksa) + BUTONLAR
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
