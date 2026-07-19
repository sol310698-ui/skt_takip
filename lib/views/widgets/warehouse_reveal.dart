import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  DEPO CANLANDIRMASI — tam ekran, 3 aşamalı "depoda bul" animasyonu.
/// ────────────────────────────────────────────────────────────────────
///  showLocationFlythrough (location_reveal.dart) küçük, saydam-zeminli
///  bir KART olarak açılıyordu. Depo için istenen daha detaylı, TAM
///  EKRAN bir akış:
///
///   1) GENEL BAKIŞ  — kamera deponun TAM ORTASINDA, tüm sütunlar görünür.
///   2) KAYDIRMA     — kamera hedef sütunun olduğu tarafa (sola/sağa)
///                     yatay olarak kayar (henüz yakınlaşma yok).
///   3) YAKINLAŞMA   — hedef sütuna zoom yapılır, sütun içindeki raflar
///                     belirginleşir, hedef raf vurgulanır.
///   4) PALET        — hedef rafın üstünde palet etiketi/ikonu iner,
///                     nabız atar (haptic ile).
///
///  Sahte 3B/perspektif KULLANILMAZ (düz widget'larda çarpık görünür);
///  sadece Alignment kayması + ölçek (scale) ile "kamera hareketi"
///  hissi verilir — location_reveal.dart ile aynı dil.
/// ════════════════════════════════════════════════════════════════════
Future<void> showWarehouseFlythrough(
  BuildContext context, {
  required String warehouseName,
  required int cols, // deponun sutun sayisi
  required int rows, // deponun en buyuk raf numarasi
  int? targetCol, // 1-based; null = zemin (sutun/raf yok)
  int? targetRow, // 1-based
  required String palletCode,
  String? shelfLabel, // orn. "Sütun 2 · Raf 3" veya "Zemin"
  int? quantity,
  String? productName,
  List<String> localPhotos = const [],
  Color? accent,
  List<String> allWarehouses = const [],
  int targetWarehouseIndex = 0,
}) {
  final safeCols = cols.clamp(1, 40);
  final safeRows = rows.clamp(1, 40);
  final onFloor = targetCol == null || targetRow == null;
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _WarehouseFlythroughScreen(
          warehouseName: warehouseName,
          cols: safeCols,
          rows: safeRows,
          targetCol: onFloor ? 1 : targetCol!.clamp(1, safeCols),
          targetRow: onFloor ? 1 : targetRow!.clamp(1, safeRows),
          onFloor: onFloor,
          palletCode: palletCode,
          shelfLabel: shelfLabel,
          quantity: quantity,
          productName: productName,
          localPhotos: localPhotos,
          accent: accent ?? AppTheme.primary,
          allWarehouses: allWarehouses,
          targetWarehouseIndex: allWarehouses.isEmpty
              ? 0
              : targetWarehouseIndex.clamp(0, allWarehouses.length - 1),
        ),
      ),
    ),
  );
}

class _WarehouseFlythroughScreen extends StatefulWidget {
  final String warehouseName;
  final int cols, rows, targetCol, targetRow;
  final bool onFloor;
  final String palletCode;
  final String? shelfLabel;
  final int? quantity;
  final String? productName;
  final List<String> localPhotos;
  final Color accent;
  final List<String> allWarehouses;
  final int targetWarehouseIndex;

  const _WarehouseFlythroughScreen({
    required this.warehouseName,
    required this.cols,
    required this.rows,
    required this.targetCol,
    required this.targetRow,
    required this.onFloor,
    required this.palletCode,
    required this.accent,
    this.shelfLabel,
    this.quantity,
    this.productName,
    this.localPhotos = const [],
    this.allWarehouses = const [],
    this.targetWarehouseIndex = 0,
  });

  @override
  State<_WarehouseFlythroughScreen> createState() =>
      _WarehouseFlythroughScreenState();
}

class _WarehouseFlythroughScreenState
    extends State<_WarehouseFlythroughScreen> with TickerProviderStateMixin {
  late final AnimationController _main;
  late final AnimationController _pulse;
  bool _landedHaptic = false;

  bool get _hasWarehouses => widget.allWarehouses.length > 1;

  // ── Faz sınırları (0..1) ──────────────────────────────────────────
  // 1) GENEL BAKIS: 0.00-0.12 (baslik + depo seridi belirir)
  // 2) KAYDIRMA:    0.12-0.42 (kamera sola/saga kayar, henuz zoom yok)
  // 3) YAKINLASMA:  0.42-0.78 (hedef suna zoom)
  // 4) PALET:       0.78-1.00 (palet etiketi iner + nabiz)
  double get _tIntro => 0.12;
  double get _tPanStart => 0.12;
  double get _tPanEnd => 0.42;
  double get _tZoomStart => 0.42;
  double get _tZoomEnd => 0.78;
  double get _tPalletEnd => 1.0;
  double get _tInfoStart => 0.72;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _main.forward();
    _main.addListener(_checkLanding);
    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) _pulse.repeat(reverse: true);
    });
    HapticFeedback.selectionClick();
  }

  void _checkLanding() {
    if (!_landedHaptic && _main.value >= _tZoomEnd) {
      _landedHaptic = true;
      HapticFeedback.mediumImpact();
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

  String get _stageLabel {
    final t = _main.value;
    if (t < _tPanStart) return 'Depo genel görünüm';
    if (t < _tZoomStart) {
      return widget.onFloor
          ? 'Zemine gidiliyor…'
          : (widget.targetCol <= (widget.cols / 2)
              ? 'Sol tarafa geçiliyor…'
              : 'Sağ tarafa geçiliyor…');
    }
    if (t < _tZoomEnd) return widget.onFloor ? 'Zemin' : 'Sütun · Raf';
    return 'Palet bulundu';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.isLight ? AppTheme.background : Colors.black,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_main, _pulse]),
          builder: (context, _) {
            final t = _main.value;
            final pulse = _pulse.value;
            final introIn = _seg(t, 0.0, _tIntro, Curves.easeOutCubic);
            final pan = _seg(t, _tPanStart, _tPanEnd, Curves.easeInOutCubic);
            final zoom =
                _seg(t, _tZoomStart, _tZoomEnd, Curves.easeInOutCubic);
            final palletIn =
                _seg(t, _tZoomEnd, _tPalletEnd, Curves.easeOutBack);
            final infoIn = _seg(t, _tInfoStart, 1.0, Curves.easeOutCubic);

            return Column(
              children: [
                _header(introIn, pan),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _warehouseFloor(pan, zoom, palletIn, pulse),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Opacity(
                    opacity: infoIn.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, (1 - infoIn) * 16),
                      child: _infoCard(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  BAŞLIK — depo adı + varsa depo şeridi + aşama etiketi
  // ════════════════════════════════════════════════════════════════
  Widget _header(double introIn, double pan) {
    return Opacity(
      opacity: introIn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.warehouseName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _stageLabel,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _dismiss,
              icon: Icon(Icons.close_rounded,
                  color: AppTheme.textTertiary, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  DEPO ZEMİNİ — tam ekran sütun/raf ızgarası. Önce ortadan, sonra
  //  hedef sütunun tarafına kayar, sonra o sütuna yakınlaşır.
  // ════════════════════════════════════════════════════════════════
  Widget _warehouseFloor(double pan, double zoom, double palletIn, double pulse) {
    final acc = widget.accent;
    // Hedef sutun ekranin sol yarisinda mi sag yarisinda mi?
    final targetAx = widget.cols == 1
        ? 0.0
        : ((widget.targetCol - 0.5) / widget.cols) * 2 - 1;
    final targetAy = widget.rows == 1
        ? 0.0
        : ((widget.targetRow - 0.5) / widget.rows) * 2 - 1;

    // Once (pan asamasi) yatayda kaymaya baslar, zoom asamasinda tam
    // hedefe kilitlenir ve olcek buyur.
    final ax = targetAx * pan;
    final ay = targetAy * pan * 0.6; // dikeyde daha az kayma (daha dogal)
    final scale = 1.0 + zoom * 2.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Container(
        color: AppTheme.surfaceAlt,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            final cellW =
                ((constraints.maxWidth - gap * (widget.cols + 1)) /
                        widget.cols)
                    .clamp(18.0, 64.0);
            final cellH =
                ((constraints.maxHeight - gap * (widget.rows + 1)) /
                        widget.rows)
                    .clamp(14.0, 44.0);
            final gridW = cellW * widget.cols + gap * (widget.cols + 1);
            final gridH = cellH * widget.rows + gap * (widget.rows + 1);
            final targetLeft =
                gap + (widget.targetCol - 1) * (cellW + gap);
            final targetTop = gap + (widget.targetRow - 1) * (cellH + gap);

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
                          _shelfCell(c, r, cellW, cellH, gap, acc, pan, zoom),

                      // ── Palet etiketi — hedef hucrenin ustune iner ──
                      Positioned(
                        left: targetLeft + cellW / 2 - 46,
                        top: targetTop - 40 - (1 - palletIn) * 30,
                        child: Opacity(
                          opacity: palletIn.clamp(0.0, 1.0),
                          child: _palletChip(acc, pulse),
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

  Widget _shelfCell(int c, int r, double cellW, double cellH, double gap,
      Color acc, double pan, double zoom) {
    final isTargetCol = (c + 1) == widget.targetCol;
    final isTarget = isTargetCol && (r + 1) == widget.targetRow;
    // Kaydirma asamasinda hedef sutun hafifce vurgulanir (once "hangi
    // tarafa gidiyoruz" hissi verir); yakinlasinca sadece hedef hucre
    // tam parlak, digerleri sonukleslir.
    final colHighlight = isTargetCol ? (0.5 + 0.5 * pan) : 0.0;
    final dim = isTarget
        ? 1.0
        : (isTargetCol
            ? (1.0 - zoom * 0.25).clamp(0.55, 1.0)
            : (1.0 - zoom * 0.65).clamp(0.28, 1.0));

    return Positioned(
      left: gap + c * (cellW + gap),
      top: gap + r * (cellH + gap),
      width: cellW,
      height: cellH,
      child: Opacity(
        opacity: dim,
        child: Container(
          decoration: BoxDecoration(
            color: isTarget
                ? acc
                : Color.lerp(AppTheme.hairline, acc.withOpacity(0.35),
                    colHighlight),
            borderRadius: BorderRadius.circular(4),
            border: isTarget
                ? Border.all(color: Colors.white.withOpacity(0.85), width: 1.4)
                : null,
            boxShadow: isTarget ? AppTheme.glow(acc) : null,
          ),
        ),
      ),
    );
  }

  Widget _palletChip(Color acc, double pulse) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: acc,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        boxShadow: [
          BoxShadow(color: acc.withOpacity(0.45 + 0.25 * pulse), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            widget.palletCode,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  ALT BİLGİ KARTI — ürün adı/fotoğrafı + konum özeti + butonlar
  // ════════════════════════════════════════════════════════════════
  Widget _infoCard() {
    final photo = widget.localPhotos.isNotEmpty ? widget.localPhotos.first : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(accentColor: widget.accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (photo != null)
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                    border: Border.all(color: AppTheme.hairline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(photo),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppTheme.surfaceAlt),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.productName != null)
                      Text(
                        widget.productName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    Text(
                      widget.shelfLabel ??
                          (widget.onFloor
                              ? 'Zemin · ${widget.palletCode}'
                              : 'Sütun ${widget.targetCol} · Raf ${widget.targetRow} · ${widget.palletCode}'),
                      style: TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary),
                    ),
                    if (widget.quantity != null)
                      Text(
                        '${widget.quantity} adet',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
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
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
