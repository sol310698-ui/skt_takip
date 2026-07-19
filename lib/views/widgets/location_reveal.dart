import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  KONUM CANLANDIRMA — "CINEMATIC FLY-THROUGH" (Oyun Kamerası)
/// ────────────────────────────────────────────────────────────────────
///  1. MAĞAZA KUŞ BAKIŞI: Reyonlar dikey şeritler halinde uzun sütunlar
///  2. REYONA UÇUŞ: Kamera hedef reyona doğru yaklaşır (zoom + pan)
///  3. REYON İÇİ — 1. SÜTUN: Kamera reyon içine girer, 1. sütun gösterilir
///  4. SÜTUN KAYMASI: Kamera yatayda hedef sütuna kayar (slide)
///  5. HEDEF RAF: Hedef hücre parlar, pin düşer, nabız atar
///
///  Kullanım:
///    showLocationFlythrough(context,
///      title: 'BAKLİYAT', cols: 5, rows: 6,
///      targetCol: 3, targetRow: 4,
///      subtitle: 'Sütun 3 · Raf 4',
///      allAisles: ['İÇECEK','BAKLİYAT','TEMİZLİK','ŞARKÜTERİ'],
///      targetAisleIndex: 1,
///    );
/// ════════════════════════════════════════════════════════════════════
Future<void> showLocationFlythrough(
  BuildContext context, {
  required String title,
  required int cols,
  required int rows,
  required int targetCol,
  required int targetRow,
  String? subtitle,
  String? productName,
  String? photoPath,
  Color? accent,
  /// Tüm reyon isimleri (dikey şeritler). Boşsa doğrudan reyon içi başlar.
  List<String> allAisles = const [],
  int targetAisleIndex = 0,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.95),
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _LocationFlythroughScreen(
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

class _LocationFlythroughScreen extends StatefulWidget {
  final String title;
  final int cols, rows, targetCol, targetRow;
  final String? subtitle, productName, photoPath;
  final Color accent;
  final List<String> allAisles;
  final int targetAisleIndex;

  const _LocationFlythroughScreen({
    required this.title,
    required this.cols,
    required this.rows,
    required this.targetCol,
    required this.targetRow,
    required this.accent,
    this.subtitle,
    this.productName,
    this.photoPath,
    required this.allAisles,
    required this.targetAisleIndex,
  });

  @override
  State<_LocationFlythroughScreen> createState() => _LocationFlythroughScreenState();
}

class _LocationFlythroughScreenState extends State<_LocationFlythroughScreen>
    with TickerProviderStateMixin {
  // ── Animasyon Kontrolleri ──
  late final AnimationController _main;
  late final AnimationController _pulse;
  late final AnimationController _glow;
  late final AnimationController _float;
  late final AnimationController _scanLine;

  // ── Değerler ──
  bool get _hasOverview => widget.allAisles.isNotEmpty;
  bool _photoExists = false;
  bool _photoChecked = false;

  // ── Faz Zamanlamaları (0..1) ──
  // Faz 1: Başlık belirir (0.00 - 0.10)
  // Faz 2: Mağaza kuş bakışı — dikey reyonlar (0.10 - 0.25)
  // Faz 3: Reyona uçuş (0.25 - 0.45)
  // Faz 4: Reyon içi — 1. sütun gösterilir (0.45 - 0.60)
  // Faz 5: Sütun kayması — hedef sütuna (0.60 - 0.80)
  // Faz 6: Hedef raf vurgusu + pin (0.80 - 1.00)
  double get _tTitleEnd => _hasOverview ? 0.10 : 0.14;
  double get _tAisleViewStart => _tTitleEnd;
  double get _tAisleViewEnd => _hasOverview ? 0.28 : 0.0;
  double get _tFlyStart => _hasOverview ? 0.28 : 0.14;
  double get _tFlyEnd => _hasOverview ? 0.48 : 0.38;
  double get _tEnterStart => _hasOverview ? 0.48 : 0.38;
  double get _tEnterEnd => _hasOverview ? 0.62 : 0.52;
  double get _tSlideStart => _hasOverview ? 0.62 : 0.52;
  double get _tSlideEnd => _hasOverview ? 0.82 : 0.72;
  double get _tTargetStart => _hasOverview ? 0.82 : 0.72;
  double get _tTargetEnd => 1.0;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: _hasOverview ? 6000 : 4500,
      ),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scanLine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _checkPhoto();
    _main.forward();

    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulse.repeat(reverse: true);
        _glow.repeat(reverse: true);
      }
    });

    HapticFeedback.lightImpact();
  }

  Future<void> _checkPhoto() async {
    if (widget.photoPath != null) {
      try {
        final file = File(widget.photoPath!);
        final exists = await file.exists();
        if (mounted) {
          setState(() {
            _photoExists = exists;
            _photoChecked = true;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _photoChecked = true);
      }
    } else {
      setState(() => _photoChecked = true);
    }
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    _glow.dispose();
    _float.dispose();
    _scanLine.dispose();
    super.dispose();
  }

  void _replay() {
    _pulse.stop();
    _pulse.value = 0;
    _glow.stop();
    _glow.value = 0;
    _main.forward(from: 0);
    HapticFeedback.mediumImpact();
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  double _seg(double t, double a, double b, [Curve c = Curves.easeInOut]) {
    if (a >= b) return t >= b ? 1.0 : 0.0;
    if (t <= a) return 0.0;
    if (t >= b) return 1.0;
    return c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accent;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Arka plan — dokunulabilir alan
          GestureDetector(
            onTap: _dismiss,
            child: Container(color: Colors.black.withOpacity(0.01)),
          ),

          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([_main, _pulse, _glow, _float, _scanLine]),
              builder: (context, _) {
                final t = _main.value;

                // ── FAZ HESAPLAMALARI ──
                final titleIn = _seg(t, 0.0, _tTitleEnd, Curves.easeOutBack);
                final titleUp = _seg(t, _tEnterStart, _tSlideEnd);

                // Faz 2: Dikey reyonlar kuş bakışı
                final aisleView = _hasOverview
                    ? _seg(t, _tAisleViewStart, _tAisleViewEnd, Curves.easeOutCubic)
                    : 0.0;
                final aisleFly = _hasOverview
                    ? _seg(t, _tAisleViewStart, _tFlyEnd, Curves.easeInOutCubic)
                    : 0.0;

                // Faz 3: Reyona uçuş
                final flyProgress = _hasOverview
                    ? _seg(t, _tFlyStart, _tFlyEnd, Curves.easeInOutCubic)
                    : _seg(t, _tFlyStart, _tFlyEnd, Curves.easeInOutCubic);

                // Faz 4: Reyon içine giriş (1. sütun)
                final enterProgress = _seg(t, _tEnterStart, _tEnterEnd, Curves.easeOutCubic);

                // Faz 5: Sütun kayması
                final slideProgress = _seg(t, _tSlideStart, _tSlideEnd, Curves.easeInOutCubic);

                // Faz 6: Hedef vurgusu
                final targetReveal = _seg(t, _tTargetStart, _tTargetEnd, Curves.easeOutBack);
                final pinDrop = _seg(t, _tTargetStart + 0.08, _tTargetEnd, Curves.bounceOut);

                // Kamera transform değerleri
                // Başlangıç: Uzak, tepeden, tüm reyonları gör
                // Uçuş: Hedef reyona yaklaş
                // Giriş: Reyon içine gir, 1. sütun merkezde
                // Kayma: Hedef sütuna yatay kay
                final cameraZoom = 0.3 + flyProgress * 1.5 + enterProgress * 1.2 + slideProgress * 0.5;
                final cameraTilt = (1 - enterProgress) * 0.9; // Tepeden bakış -> önden bakış
                final cameraPanY = -0.3 * flyProgress; // Yukarı kayma
                final cameraPanX = _hasOverview
                    ? _aislePanX(flyProgress) + _columnSlideX(slideProgress)
                    : _columnSlideX(slideProgress);

                return Column(
                  children: [
                    const SizedBox(height: 20),

                    // ── DEV BAŞLIK ──
                    Transform.scale(
                      scale: (0.4 + 0.6 * titleIn) * (1 - 0.5 * titleUp),
                      child: Opacity(
                        opacity: titleIn,
                        child: Column(
                          children: [
                            Text(
                              widget.title.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                height: 1.0,
                                shadows: [
                                  Shadow(color: acc, blurRadius: 30),
                                  Shadow(color: acc.withOpacity(0.5), blurRadius: 60),
                                ],
                              ),
                            ),
                            if (widget.subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: AnimatedOpacity(
                                  opacity: targetReveal,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: acc.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: acc.withOpacity(0.6),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: acc.withOpacity(0.2),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      widget.subtitle!,
                                      style: TextStyle(
                                        color: acc,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── ANA SAHNE (Oyun Kamerası) ──
                    Expanded(
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // KATMAN 1: Diş kenar karartma (vignette)
                            CustomPaint(
                              painter: _VignettePainter(intensity: 0.6),
                              size: Size.infinite,
                            ),

                            // KATMAN 2: Dikey reyonlar kuş bakışı
                            if (_hasOverview && aisleView < 1.0)
                              Opacity(
                                opacity: (1.0 - flyProgress * 1.5).clamp(0, 1),
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.0015)
                                    ..rotateX(0.7 * (1 - aisleFly * 0.5))
                                    ..scale(0.4 + aisleFly * 1.5)
                                    ..translate(0.0, -50.0 * aisleFly),
                                  child: Center(
                                    child: _aislesOverview(acc, aisleFly),
                                  ),
                                ),
                              ),

                            // KATMAN 3: Reyon içi (kamera transformlu)
                            Opacity(
                              opacity: enterProgress.clamp(0, 1),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.002)
                                  ..rotateX(cameraTilt)
                                  ..scale(cameraZoom.clamp(0.5, 4.0))
                                  ..translate(cameraPanX * 200, cameraPanY * 100),
                                child: Center(
                                  child: _aisleInterior(
                                    acc,
                                    slideProgress,
                                    targetReveal,
                                    pinDrop,
                                  ),
                                ),
                              ),
                            ),

                            // KATMAN 4: Tarama çizgisi (scanner line)
                            if (slideProgress > 0.1 && slideProgress < 0.9)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ScannerLinePainter(
                                    progress: _scanLine.value,
                                    color: acc,
                                  ),
                                ),
                              ),

                            // KATMAN 5: Hedef vurgusu (ışık halkası)
                            if (targetReveal > 0.3)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _TargetGlowPainter(
                                    color: acc,
                                    intensity: targetReveal,
                                    pulse: _pulse.value,
                                  ),
                                ),
                              ),

                            // KATMAN 6: HUD overlay (oyun UI tarzı)
                            if (enterProgress > 0.5)
                              Positioned(
                                top: 8,
                                left: 20,
                                right: 20,
                                child: Opacity(
                                  opacity: (enterProgress - 0.5) * 2,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _hudText('SÜTUN ${widget.targetCol}/${widget.cols}'),
                                      _hudText('RAF ${widget.targetRow}/${widget.rows}'),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // ── ALT BİLGİ + BUTONLAR ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.photoPath != null && _photoExists)
                            AnimatedOpacity(
                              opacity: targetReveal,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                width: 70,
                                height: 70,
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.4),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: acc.withOpacity(0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.file(
                                  File(widget.photoPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) =>
                                      Container(
                                    color: Colors.white.withOpacity(0.1),
                                    child: const Icon(
                                      Icons.image_not_supported,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          if (widget.productName != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                widget.productName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                          Row(
                            children: [
                              Expanded(
                                child: _GlassButton(
                                  onTap: _replay,
                                  icon: Icons.replay_rounded,
                                  label: 'Tekrar',
                                  accent: acc,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ActionButton(
                                  onTap: _dismiss,
                                  icon: Icons.check_rounded,
                                  label: 'Tamam',
                                  accent: acc,
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
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  KATMAN 2: DİKEY REYONLAR KUŞ BAKIŞI
  // ════════════════════════════════════════════════════════════════════
  Widget _aislesOverview(Color acc, double flyProgress) {
    final aisles = widget.allAisles;
    final targetIdx = widget.targetAisleIndex;

    return SizedBox(
      width: 340,
      height: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Üst etiket
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white30, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_rounded, color: Colors.white60, size: 18),
                SizedBox(width: 8),
                Text(
                  'MAĞAZA PLANI',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          // Dikey reyon şeritleri
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(aisles.length, (i) {
                final isTarget = i == targetIdx;
                final distance = (i - targetIdx).abs();
                final opacity = isTarget
                    ? 1.0
                    : (0.3 - distance * 0.08).clamp(0.1, 0.3);
                final pulseVal = isTarget ? _pulse.value : 0.0;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 50 + (isTarget ? 20 * flyProgress : 0),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isTarget
                        ? acc.withOpacity(0.7 + 0.2 * pulseVal)
                        : Colors.white.withOpacity(opacity),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isTarget
                          ? Colors.white.withOpacity(0.8 + 0.2 * pulseVal)
                          : Colors.white.withOpacity(0.1),
                      width: isTarget ? 2.5 : 1,
                    ),
                    boxShadow: isTarget
                        ? [
                            BoxShadow(
                              color: acc.withOpacity(0.4 + 0.3 * pulseVal),
                              blurRadius: 25 + 10 * pulseVal,
                              spreadRadius: 4 + 2 * pulseVal,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isTarget)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Icon(
                            Icons.location_searching_rounded,
                            color: Colors.black.withOpacity(0.7),
                            size: 20,
                          ),
                        ),
                      RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          aisles[i].toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isTarget
                                ? Colors.black.withOpacity(0.9)
                                : Colors.white.withOpacity(0.6),
                            fontSize: 12,
                            fontWeight: isTarget ? FontWeight.w900 : FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      if (isTarget)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: acc.withOpacity(0.8),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),

          // Alt ok (hedef yönü)
          if (flyProgress < 0.5)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AnimatedOpacity(
                opacity: (0.5 - flyProgress) * 2,
                duration: Duration.zero,
                child: Column(
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      color: acc.withOpacity(0.8),
                      size: 28,
                    ),
                    Text(
                      'HEDEF REYONA İNİYOR',
                      style: TextStyle(
                        color: acc.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  KATMAN 3: REYON İÇİ (1. Sütun -> Hedef Sütun Kayması)
  // ════════════════════════════════════════════════════════════════════
  Widget _aisleInterior(
    Color acc,
    double slideProgress,
    double targetReveal,
    double pinDrop,
  ) {
    const cellW = 52.0, cellH = 48.0, gap = 8.0;
    final totalW = widget.cols * (cellW + gap) + gap;

    // Sütun kayması: 1. sütun merkezde -> hedef sütun merkezde
    // slideProgress: 0 = 1. sütun, 1 = hedef sütun
    final startCol = 0; // 0-based (1. sütun)
    final endCol = widget.targetCol - 1; // 0-based hedef
    final currentCol = startCol + (endCol - startCol) * slideProgress;
    final colOffset = (currentCol - (widget.cols - 1) / 2) * (cellW + gap);

    return Transform.translate(
      offset: Offset(-colOffset, 0),
      child: SizedBox(
        width: totalW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reyon başlığı
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    acc.withOpacity(0.3),
                    acc.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: acc.withOpacity(0.5), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.view_column_rounded,
                    color: acc.withOpacity(0.9),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.title.toUpperCase(),
                    style: TextStyle(
                      color: acc.withOpacity(0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // Sütun numaraları
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.cols, (c) {
                final isTarget = c + 1 == widget.targetCol;
                final isVisible = (c - currentCol).abs() < 3; // Yakın sütunlar

                return Opacity(
                  opacity: isVisible ? 1.0 : 0.2,
                  child: Container(
                    width: cellW + gap,
                    alignment: Alignment.center,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isTarget
                            ? acc.withOpacity(0.3 + 0.2 * _pulse.value)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${c + 1}',
                        style: TextStyle(
                          color: isTarget
                              ? acc
                              : Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          fontWeight: isTarget ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),

            // Raf satırları
            ...List.generate(widget.rows, (r) {
              final rowNo = r + 1;
              final isTargetRow = rowNo == widget.targetRow;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Raf numarası
                    Container(
                      width: 32,
                      height: cellH,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isTargetRow
                            ? acc.withOpacity(0.25)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isTargetRow
                              ? acc.withOpacity(0.5)
                              : Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '$rowNo',
                        style: TextStyle(
                          color: isTargetRow
                              ? acc
                              : Colors.white.withOpacity(0.35),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    // Hücreler
                    ...List.generate(widget.cols, (c) {
                      final colNo = c + 1;
                      final isTarget = colNo == widget.targetCol && rowNo == widget.targetRow;
                      final isVisible = (c - currentCol).abs() < 3;
                      final pulseVal = _pulse.value;
                      final glowVal = _glow.value;

                      return Opacity(
                        opacity: isVisible ? 1.0 : 0.15,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                          child: _interiorCell(
                            isTarget,
                            acc,
                            targetReveal,
                            pinDrop,
                            pulseVal,
                            glowVal,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),

            // Alt bilgi çubuğu
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white.withOpacity(0.3),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.cols} SÜTUN · ${widget.rows} RAF',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _interiorCell(
    bool isTarget,
    Color acc,
    double targetReveal,
    double pinDrop,
    double pulseVal,
    double glowVal,
  ) {
    const cellW = 52.0, cellH = 48.0;
    final pulseScale = isTarget ? (0.92 + 0.12 * pulseVal) : 1.0;
    final glowIntensity = isTarget
        ? (0.5 + 0.4 * glowVal + 0.2 * pulseVal).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: cellW,
      height: cellH + 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Hücre kutusu
          Transform.scale(
            scale: pulseScale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: cellW,
              height: cellH,
              decoration: BoxDecoration(
                color: isTarget
                    ? acc.withOpacity(0.85 + 0.12 * glowVal)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isTarget
                      ? Colors.white.withOpacity(0.85 + 0.15 * pulseVal)
                      : Colors.white.withOpacity(0.12),
                  width: isTarget ? 2.5 : 1.0,
                ),
                boxShadow: isTarget
                    ? [
                        BoxShadow(
                          color: acc.withOpacity(glowIntensity * 0.6),
                          blurRadius: 20 + 10 * pulseVal,
                          spreadRadius: 3 + 3 * pulseVal,
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.1 * pulseVal),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: isTarget
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white.withOpacity(0.9),
                        size: 22,
                      )
                    : null,
              ),
            ),
          ),

          // Konum pini (hedef hücreye)
          if (isTarget && pinDrop > 0)
            Positioned(
              top: -32 + (1 - pinDrop) * -60,
              child: Opacity(
                opacity: pinDrop.clamp(0, 1),
                child: Transform.scale(
                  scale: 0.7 + 0.3 * pinDrop,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pin gölgesi
                      Container(
                        width: 14,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4 * pulseVal),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Pin ikonu
                      Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 36,
                        shadows: [
                          Shadow(color: acc, blurRadius: 20),
                          Shadow(color: acc.withOpacity(0.6), blurRadius: 40),
                        ],
                      ),
                      // Hedef noktası (nabız atan)
                      Container(
                        width: 8 + 5 * pulseVal,
                        height: 8 + 5 * pulseVal,
                        decoration: BoxDecoration(
                          color: acc.withOpacity(0.9 + 0.1 * pulseVal),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: acc.withOpacity(0.6 * pulseVal),
                              blurRadius: 12,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  KAMERA HESAPLAMALARI
  // ════════════════════════════════════════════════════════════════════
  double _aislePanX(double flyProgress) {
    // Hedef reyona doğru yatay kayma
    final n = widget.allAisles.length;
    if (n <= 1) return 0.0;
    final target = widget.targetAisleIndex;
    final center = (n - 1) / 2;
    return (target - center) * flyProgress * 0.8;
  }

  double _columnSlideX(double slideProgress) {
    // Sütun kayması (1. sütundan hedef sütuna)
    final startCol = 0;
    final endCol = widget.targetCol - 1;
    return (startCol - endCol) * slideProgress * 0.5;
  }

  Widget _hudText(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  BUTONLAR
// ════════════════════════════════════════════════════════════════════

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color accent;

  const _GlassButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.9), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color accent;

  const _ActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent,
              accent.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black.withOpacity(0.8), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.black.withOpacity(0.9),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  ÖZEL ÇİZİCİLER
// ════════════════════════════════════════════════════════════════════

/// Vignette efekti (kenar karartma)
class _VignettePainter extends CustomPainter {
  final double intensity;

  _VignettePainter({this.intensity = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = RadialGradient(
      colors: [
        Colors.transparent,
        Colors.black.withOpacity(intensity),
      ],
      stops: const [0.5, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _VignettePainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}

/// Tarama çizgisi (sütun kayması sırasında)
class _ScannerLinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScannerLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.3 + (size.height * 0.4) * progress;

    final paint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Yatay tarama çizgisi
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      paint,
    );

    // Glow efekti
    final glowPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerLinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Hedef ışık halkası
class _TargetGlowPainter extends CustomPainter {
  final Color color;
  final double intensity;
  final double pulse;

  _TargetGlowPainter({
    required this.color,
    required this.intensity,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final maxRadius = size.width * 0.35;

    // Dış halka
    final outerPaint = Paint()
      ..color = color.withOpacity(0.04 * intensity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      maxRadius * (0.9 + 0.1 * pulse),
      outerPaint,
    );

    // Orta halka
    final midPaint = Paint()
      ..color = color.withOpacity(0.08 * intensity * (0.7 + 0.3 * pulse))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      maxRadius * 0.5 * (0.95 + 0.05 * pulse),
      midPaint,
    );

    // İç parlama
    final innerPaint = Paint()
      ..color = Colors.white.withOpacity(0.06 * intensity * pulse)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      maxRadius * 0.15 * (0.85 + 0.15 * pulse),
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TargetGlowPainter oldDelegate) =>
      oldDelegate.intensity != intensity || oldDelegate.pulse != pulse;
}
