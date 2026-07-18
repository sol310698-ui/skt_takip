import 'dart:io';

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
  /// MAGAZA GENEL GORUNUMU: tum reyon/depo ADLARI. Verilirse canlandirma
  /// once MAGAZANIN KUS BAKISI haritasiyla baslar (tum reyonlar blok blok),
  /// kamera hedef reyona UCAR, sonra reyonun icine iner. Bos birakilirsa
  /// dogrudan reyon icinden baslar.
  List<String> overviewItems = const [],
  int overviewTargetIndex = 0,
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
          overviewItems: overviewItems,
          overviewTargetIndex:
              overviewTargetIndex.clamp(0, overviewItems.isEmpty ? 0 : overviewItems.length - 1),
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
  // Ana zaman cizelgesi: magaza gorunumu varsa ~4.8 sn (baslik -> MAGAZA
  // kus bakisi -> hedef reyona ucus -> reyon icine gecis -> hucreye inis ->
  // pin), yoksa ~3.4 sn (dogrudan reyon ici).
  late final AnimationController _main = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: (widget.overviewItems.isNotEmpty) ? 4800 : 3400));

  bool get _hasOverview => widget.overviewItems.isNotEmpty;
  // Pin nabzi (inis bittikten sonra surekli).
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));

  // Faz araliklari (0..1) — magaza gorunumu varsa kaydirilir.
  double get _tTitleIn => _hasOverview ? 0.08 : 0.12;
  double get _tMapIn => 0.20; // magaza haritasi belirir
  double get _tMapFlyEnd => 0.42; // hedef reyona ucus biter
  double get _tCross => 0.50; // harita -> reyon ici gecisi
  double get _tGridIn => _hasOverview ? 0.50 : 0.30;
  double get _tFlyEnd => _hasOverview ? 0.86 : 0.80;
  double get _tPinEnd => 0.96;

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
              // MAGAZA fazi (varsa): harita belirir -> hedef reyona ucus ->
              // reyon icine cross-fade.
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

                  // ── SAHNE: (varsa) MAGAZA HARITASI + REYON ICI ──
                  Expanded(
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // KATMAN 1 — MAGAZA KUS BAKISI: tum reyonlar blok
                          // blok; kamera hedef bloga ucar, sonra kaybolur.
                          if (_hasOverview && cross < 1.0)
                            Opacity(
                              opacity: mapIn * (1.0 - cross),
                              child: Transform(
                                alignment: _mapTargetAlignment(),
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.0012)
                                  ..rotateX(0.55 * (1 - mapFly * 0.4))
                                  ..scale(0.9 + mapFly * 2.2),
                                child: Center(child: _storeMap(acc, mapFly)),
                              ),
                            ),
                          // KATMAN 2 — REYON ICI: haritadan cross-fade ile
                          // devralir, hucreye inis burada surer.
                          Opacity(
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
                        ],
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

  // ── MAGAZA KUS BAKISI HARITASI ──
  // Tum reyonlar 2 sutunluk blok duzeninde; hedef reyon renkli ve adiyla
  // one cikar, digerleri soluk. Ucus sirasinda hedef blok hafif nabiz atar.
  static const int _mapCols = 2;

  Alignment _mapTargetAlignment() {
    final n = widget.overviewItems.length;
    if (n <= 1) return Alignment.center;
    final idx = widget.overviewTargetIndex;
    final rows = (n / _mapCols).ceil();
    final c = idx % _mapCols, r = idx ~/ _mapCols;
    final ax = _mapCols == 1 ? 0.0 : ((c + 0.5) / _mapCols) * 2 - 1;
    final ay = rows == 1 ? 0.0 : ((r + 0.5) / rows) * 2 - 1;
    return Alignment(ax, ay);
  }

  Widget _storeMap(Color acc, double mapFly) {
    final items = widget.overviewItems;
    final rows = (items.length / _mapCols).ceil();
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(rows, (r) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_mapCols, (c) {
                final idx = r * _mapCols + c;
                if (idx >= items.length) {
                  return const SizedBox(width: 140, height: 54);
                }
                final isTarget = idx == widget.overviewTargetIndex;
                final glow = isTarget ? (0.35 + 0.4 * mapFly) : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Container(
                    width: 130,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isTarget
                          ? acc.withOpacity(0.85)
                          : Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            isTarget ? Colors.white : Colors.white24,
                        width: isTarget ? 1.6 : 0.8,
                      ),
                      boxShadow: isTarget
                          ? [
                              BoxShadow(
                                color: acc.withOpacity(glow),
                                blurRadius: 22,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        items[idx],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isTarget
                              ? Colors.black
                              : Colors.white60,
                          fontSize: 13,
                          fontWeight: isTarget
                              ? FontWeight.w900
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
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
