import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  KONUM CANLANDIRMA — "KAMERA İNİŞİ" (cinematic fly-to)
/// ────────────────────────────────────────────────────────────────────
///  Google Haritalar'ın bir noktaya "uçarak inmesi" gibi: önce mekanın
///  adı DEV harflerle belirir, ardından raf/depo ızgarasına TEPEDEN bakan
///  kamera, hedef hücreye doğru süzülerek YAKINLAŞIR (ölçek + perspektif
///  eğimi aynı anda değişir — oyun kamerası hissi). İniş bitince hedefe
///  yukarıdan bir konum pini düşer, zıplar ve nabız atmaya başlar.
///
///  ORTAK SERVİSTİR: hem REYON (etiket tarama) hem DEPO (palet) konumları
///  aynı fonksiyonla canlandırılır:
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
  required int targetRow, // 1-based (1 = EN ÜST raf)
  String? subtitle,
  String? productName,
  String? photoPath,
  Color? accent,
  /// MAĞAZA GENEL GÖRÜNÜMÜ: tüm reyon/depo ADLARI. Verilirse canlandırma
  /// önce MAĞAZANIN KUŞ BAKIŞI haritasıyla başlar (tüm reyonlar blok blok),
  /// kamera hedef reyona UÇAR, sonra reyonun içine iner. Boş bırakılırsa
  /// doğrudan reyon içinden başlar.
  List<String> overviewItems = const [],
  int overviewTargetIndex = 0,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.92),
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 200),
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
          overviewItems: overviewItems,
          overviewTargetIndex: overviewTargetIndex.clamp(
              0, overviewItems.isEmpty ? 0 : overviewItems.length - 1),
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
  final List<String> overviewItems;
  final int overviewTargetIndex;

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
    this.overviewItems = const [],
    this.overviewTargetIndex = 0,
  });

  @override
  State<_LocationRevealScreen> createState() => _LocationRevealScreenState();
}

class _LocationRevealScreenState extends State<_LocationRevealScreen>
    with TickerProviderStateMixin {
  // ── Animasyon Kontrolleri ──
  late final AnimationController _main;
  late final AnimationController _pulse;
  late final AnimationController _glow;
  late final AnimationController _float;

  // ── Değerler ──
  bool get _hasOverview => widget.overviewItems.isNotEmpty;
  bool _photoExists = false;
  bool _photoChecked = false;

  // ── Faz Zamanlamaları (0..1) ──
  double get _tTitleIn => _hasOverview ? 0.08 : 0.12;
  double get _tMapIn => 0.20;
  double get _tMapFlyEnd => 0.42;
  double get _tCross => 0.50;
  double get _tGridIn => _hasOverview ? 0.50 : 0.30;
  double get _tFlyEnd => _hasOverview ? 0.86 : 0.80;
  double get _tPinEnd => 0.96;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: _hasOverview ? 5200 : 3800,
      ),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Fotoğraf kontrolü (asenkron)
    _checkPhoto();

    // Ana animasyonu başlat
    _main.forward();

    // Durum dinleyicisi — pulse ve glow başlatma
    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulse.repeat(reverse: true);
        _glow.repeat(reverse: true);
      }
    });

    // Haptic feedback — başlangıçta hafif titreşim
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
        if (mounted) {
          setState(() => _photoChecked = true);
        }
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

  /// Segment interpolasyonu (clamp'li, güvenli)
  double _seg(double t, double a, double b, [Curve c = Curves.easeInOut]) {
    if (a >= b) return t >= b ? 1.0 : 0.0;
    if (t <= a) return 0.0;
    if (t >= b) return 1.0;
    return c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.accent;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Arka plan karartma (dokunulabilir) ──
          GestureDetector(
            onTap: _dismiss,
            child: Container(
              color: Colors.black.withOpacity(0.01), // Hedef dışı tıklama
            ),
          ),

          // ── Ana içerik ──
          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([_main, _pulse, _glow, _float]),
              builder: (context, _) {
                final t = _main.value;

                // ── Faz Değerleri ──
                final titleIn = _seg(t, 0.0, _tTitleIn, Curves.easeOutBack);
                final titleUp = _seg(t, _tGridIn, _tFlyEnd);

                final mapIn = _hasOverview
                    ? _seg(t, _tTitleIn, _tMapIn)
                    : 0.0;
                final mapFly = _hasOverview
                    ? _seg(t, _tMapIn, _tMapFlyEnd, Curves.easeInOutCubic)
                    : 0.0;
                final cross = _hasOverview
                    ? _seg(t, _tMapFlyEnd, _tCross)
                    : 1.0;
                final gridIn = _hasOverview
                    ? cross
                    : _seg(t, _tTitleIn, _tGridIn);
                final fly = _seg(t, _tGridIn, _tFlyEnd, Curves.easeInOutCubic);
                final pinDrop = _seg(t, _tFlyEnd, _tPinEnd, Curves.bounceOut);

                // Kamera: uzak tepeden -> yakın önden
                final scale = 0.65 + fly * 2.0;
                final tilt = (1 - fly) * 0.75;

                // Hedef hücrenin göreli konumu (-1..1)
                final ax = widget.cols == 1
                    ? 0.0
                    : ((widget.targetCol - 0.5) / widget.cols) * 2 - 1;
                final ay = widget.rows == 1
                    ? 0.0
                    : ((widget.targetRow - 0.5) / widget.rows) * 2 - 1;

                return Column(
                  children: [
                    const SizedBox(height: 24),

                    // ── DEV BAŞLIK (gölge + glow efekti) ──
                    Transform.scale(
                      scale: (0.5 + 0.5 * titleIn) * (1 - 0.4 * titleUp),
                      child: Opacity(
                        opacity: titleIn,
                        child: ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              Colors.white,
                              acc.withOpacity(0.9),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(bounds),
                          child: Column(
                            children: [
                              Text(
                                widget.title.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                  height: 1.1,
                                ),
                              ),
                              if (widget.subtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: acc.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: acc.withOpacity(0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      widget.subtitle!,
                                      style: TextStyle(
                                        color: acc,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── SAHNE: Mağaza Haritası + Reyon İçi ──
                    Expanded(
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // KATMAN 1 — MAĞAZA KUŞ BAKIŞI
                            if (_hasOverview && cross < 1.0)
                              Opacity(
                                opacity: mapIn * (1.0 - cross).clamp(0, 1),
                                child: Transform(
                                  alignment: _mapTargetAlignment(),
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, 0.002)
                                    ..rotateX(0.5 * (1 - mapFly * 0.35))
                                    ..scale(0.85 + mapFly * 2.0),
                                  child: Center(
                                    child: _storeMap(acc, mapFly),
                                  ),
                                ),
                              ),

                            // KATMAN 2 — REYON İÇİ
                            Opacity(
                              opacity: gridIn.clamp(0, 1),
                              child: Transform(
                                alignment: Alignment(ax, ay),
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.002)
                                  ..rotateX(tilt)
                                  ..scale(scale),
                                child: Center(
                                  child: _grid(acc, pinDrop),
                                ),
                              ),
                            ),

                            // KATMAN 3 — Işık parlaması (hedef hücreye)
                            if (fly > 0.7)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _LightBurstPainter(
                                    color: acc,
                                    intensity: (fly - 0.7) / 0.3,
                                    pulse: _pulse.value,
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
                          // Ürün fotoğrafı (varsa)
                          if (widget.photoPath != null && _photoExists)
                            AnimatedOpacity(
                              opacity: pinDrop,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                width: 80,
                                height: 80,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: acc.withOpacity(0.3),
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
                                    child: const Icon(Icons.image_not_supported,
                                        color: Colors.white38),
                                  ),
                                ),
                              ),
                            ),

                          if (widget.productName != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                widget.productName!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),

                          const SizedBox(height: 6),

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

  // ── MAĞAZA KUŞ BAKIŞI HARİTASI ──
  static const int _mapCols = 2;

  Alignment _mapTargetAlignment() {
    final n = widget.overviewItems.length;
    if (n <= 1) return Alignment.center;
    final idx = widget.overviewTargetIndex.clamp(0, n - 1);
    final rows = (n / _mapCols).ceil();
    final c = idx % _mapCols;
    final r = idx ~/ _mapCols;
    final ax = _mapCols == 1 ? 0.0 : ((c + 0.5) / _mapCols) * 2 - 1;
    final ay = rows == 1 ? 0.0 : ((r + 0.5) / rows) * 2 - 1;
    return Alignment(ax, ay);
  }

  Widget _storeMap(Color acc, double mapFly) {
    final items = widget.overviewItems;
    final rows = (items.length / _mapCols).ceil();

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mağaza etiketi
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_rounded, color: Colors.white60, size: 16),
                SizedBox(width: 6),
                Text(
                  'MAĞAZA GÖRÜNÜMÜ',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(rows, (r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_mapCols, (c) {
                  final idx = r * _mapCols + c;
                  if (idx >= items.length) {
                    return const SizedBox(width: 148, height: 60);
                  }
                  final isTarget = idx == widget.overviewTargetIndex;
                  final pulseVal = isTarget ? _pulse.value : 0.0;
                  final glowIntensity = isTarget
                      ? (0.3 + 0.5 * mapFly + 0.2 * pulseVal).clamp(0.0, 1.0)
                      : 0.0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 140,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTarget
                            ? acc.withOpacity(0.85)
                            : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isTarget
                              ? Colors.white.withOpacity(0.8 + 0.2 * pulseVal)
                              : Colors.white.withOpacity(0.15),
                          width: isTarget ? 2.0 : 1.0,
                        ),
                        boxShadow: isTarget
                            ? [
                                BoxShadow(
                                  color: acc.withOpacity(glowIntensity * 0.6),
                                  blurRadius: 24 + 8 * pulseVal,
                                  spreadRadius: 3 + 2 * pulseVal,
                                ),
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.1 * pulseVal),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isTarget)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.location_searching_rounded,
                                  color: Colors.black.withOpacity(0.7),
                                  size: 16,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                items[idx],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isTarget
                                      ? Colors.black.withOpacity(0.9)
                                      : Colors.white.withOpacity(0.5),
                                  fontSize: 14,
                                  fontWeight: isTarget
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── REYON/DEPO IZGARASI ──
  Widget _grid(Color acc, double pinDrop) {
    const cellW = 48.0, cellH = 44.0, gap = 6.0;
    final totalW = widget.cols * (cellW + gap) + gap;
    final screenW = MediaQuery.of(context).size.width;
    final scaleFactor = totalW > screenW * 0.85
        ? (screenW * 0.85) / totalW
        : 1.0;

    return Transform.scale(
      scale: scaleFactor,
      child: SizedBox(
        width: totalW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reyon etiketi
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: acc.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: acc.withOpacity(0.4), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.grid_view_rounded,
                      color: acc.withOpacity(0.8), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'REYON İÇİ',
                    style: TextStyle(
                      color: acc.withOpacity(0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            ...List.generate(widget.rows, (r) {
              final rowNo = r + 1;
              final isTargetRow = rowNo == widget.targetRow;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Satır numarası
                        Container(
                          width: 28,
                          height: cellH,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: isTargetRow
                                ? acc.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$rowNo',
                            style: TextStyle(
                              color: isTargetRow
                                  ? acc
                                  : Colors.white.withOpacity(0.3),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...List.generate(widget.cols, (c) {
                          final colNo = c + 1;
                          final isTarget = colNo == widget.targetCol &&
                              rowNo == widget.targetRow;

                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: gap / 2),
                            child: _cellBox(isTarget, acc, pinDrop, colNo),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Raf tahtası
                    Container(
                      width: totalW - gap - 34,
                      height: 3,
                      margin: const EdgeInsets.only(left: 34),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(isTargetRow ? 0.3 : 0.1),
                            Colors.white.withOpacity(isTargetRow ? 0.15 : 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _cellBox(bool isTarget, Color acc, double pinDrop, int colNo) {
    const cellW = 48.0, cellH = 44.0;
    final pulseVal = _pulse.value;
    final glowVal = _glow.value;
    final floatVal = _float.value;

    // Nabız efekti
    final pulseScale = isTarget ? (0.95 + 0.08 * pulseVal) : 1.0;
    final glowIntensity = isTarget
        ? (0.4 + 0.4 * glowVal + 0.2 * pulseVal).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: cellW,
      height: cellH + 22, // pin için üst boşluk
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Hücre kutusu
          Transform.scale(
            scale: pulseScale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: cellW,
              height: cellH,
              decoration: BoxDecoration(
                color: isTarget
                    ? acc.withOpacity(0.85 + 0.1 * glowVal)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isTarget
                      ? Colors.white.withOpacity(0.8 + 0.2 * pulseVal)
                      : Colors.white.withOpacity(0.15),
                  width: isTarget ? 2.0 : 1.0,
                ),
                boxShadow: isTarget
                    ? [
                        BoxShadow(
                          color: acc.withOpacity(glowIntensity * 0.5),
                          blurRadius: 18 + 8 * pulseVal,
                          spreadRadius: 2 + 2 * pulseVal,
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.08 * pulseVal),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: isTarget && _photoExists && _photoChecked
                  ? Image.file(
                      File(widget.photoPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => _cellPlaceholder(acc),
                    )
                  : _cellPlaceholder(acc, isTarget: isTarget, colNo: colNo),
            ),
          ),

          // Sütun numarası (üstte)
          Positioned(
            top: -16,
            child: Opacity(
              opacity: isTarget ? 0.9 : 0.3,
              child: Text(
                '$colNo',
                style: TextStyle(
                  color: isTarget ? acc : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          // Konum pini (yukarıdan düşer + nabız + salınım)
          if (isTarget && pinDrop > 0)
            Positioned(
              top: -30 + (1 - pinDrop) * -50 + floatVal * -4,
              child: Opacity(
                opacity: pinDrop.clamp(0, 1),
                child: Transform.scale(
                  scale: 0.8 + 0.2 * pinDrop,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pin gölgesi
                      Container(
                        width: 12,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3 * pulseVal),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 32,
                        shadows: [
                          Shadow(color: acc, blurRadius: 18),
                          Shadow(color: acc.withOpacity(0.5), blurRadius: 30),
                        ],
                      ),
                      // Hedef noktası (nabız)
                      Container(
                        width: 6 + 4 * pulseVal,
                        height: 6 + 4 * pulseVal,
                        decoration: BoxDecoration(
                          color: acc.withOpacity(0.8 + 0.2 * pulseVal),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: acc.withOpacity(0.5 * pulseVal),
                              blurRadius: 10,
                              spreadRadius: 2,
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

  Widget _cellPlaceholder(Color acc,
      {bool isTarget = false, int? colNo}) {
    return Container(
      alignment: Alignment.center,
      child: isTarget
          ? Icon(
              Icons.check_circle_rounded,
              color: Colors.white.withOpacity(0.9),
              size: 20,
            )
          : Text(
              '${colNo ?? ''}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  ÖZEL BUTONLAR
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
//  IŞIK PARLAMASI ÇİZİCİ (Hedef hücreye odaklanma efekti)
// ════════════════════════════════════════════════════════════════════

class _LightBurstPainter extends CustomPainter {
  final Color color;
  final double intensity;
  final double pulse;

  _LightBurstPainter({
    required this.color,
    required this.intensity,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.6;

    // Dış halka (soluk)
    final outerPaint = Paint()
      ..color = color.withOpacity(0.03 * intensity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      maxRadius * (0.8 + 0.2 * pulse),
      outerPaint,
    );

    // İç halka (daha yoğun)
    final innerPaint = Paint()
      ..color = color.withOpacity(0.06 * intensity * (0.7 + 0.3 * pulse))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      maxRadius * 0.4 * (0.9 + 0.1 * pulse),
      innerPaint,
    );

    // Merkez nokta (parlak)
    final corePaint = Paint()
      ..color = Colors.white.withOpacity(0.1 * intensity * pulse)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      maxRadius * 0.08 * (0.8 + 0.2 * pulse),
      corePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LightBurstPainter oldDelegate) =>
      oldDelegate.intensity != intensity || oldDelegate.pulse != pulse;
}
