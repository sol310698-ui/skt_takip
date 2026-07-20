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
///   1) AÇILIŞ      — iki raf duvarı (sol/sağ) merkezde kapalı başlar,
///                     dışa doğru (soldan sağa) açılarak koridoru
///                     ortaya çıkarır. Sütunlar yarı yarıya solda/sağda
///                     paylaştırılır (örn. 6 sütun → 3 sol, 3 sağ).
///   2) KAYDIRMA     — kamera koridorda hedef tarafa (sola/sağa) ilerler;
///                     hedef duvar kameraya döner/parlar, diğeri sönükleşir.
///   3) YAKINLAŞMA   — hedef sütuna zoom yapılır, sütun içindeki raflar
///                     belirginleşir, hedef raf vurgulanır.
///   4) PALET        — hedef rafın üstünde palet etiketi iner (rafta
///                     kaçıncı palet olduğu da gösterilir, örn. "2. Palet").
///   5) FOTOĞRAF     — paletin gerçek fotoğrafı varsa büyütülüp gösterilir.
///
///  "3B" izlenimi gerçek 3B render değil; Matrix4 perspective girişi +
///  rotateY ile iki duvarın koridorun ortasından menteşeliymiş gibi
///  açılıp kapanmasından gelir (düşük maliyetli, tüm cihazlarda akıcı).
/// ════════════════════════════════════════════════════════════════════
Future<void> showWarehouseFlythrough(
  BuildContext context, {
  required String warehouseName,
  required int cols, // deponun sutun sayisi
  required int rows, // deponun en buyuk raf numarasi
  Map<int, int> colShelfCounts = const {}, // sutun no -> o sutunun GERCEK raf sayisi
  int? targetCol, // 1-based; null = zemin (sutun/raf yok)
  int? targetRow, // 1-based
  required String palletCode,
  String? shelfLabel, // orn. "Sütun 2 · Raf 3" veya "Zemin"
  int? quantity,
  String? productName,
  List<String> localPhotos = const [],
  String? palletPhotoPath, // paletin GERCEK fotografi (varsa, son asamada buyutulup gosterilir)
  int? palletPosition, // rafta kacinci palet (1-based) - "1. Palet" gibi
  int? palletsOnShelf, // rafta toplam kac palet var
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
          colShelfCounts: colShelfCounts,
          targetCol: onFloor ? 1 : targetCol!.clamp(1, safeCols),
          targetRow: onFloor ? 1 : targetRow!.clamp(1, safeRows),
          onFloor: onFloor,
          palletCode: palletCode,
          shelfLabel: shelfLabel,
          quantity: quantity,
          productName: productName,
          localPhotos: localPhotos,
          palletPhotoPath: palletPhotoPath,
          palletPosition: palletPosition,
          palletsOnShelf: palletsOnShelf,
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
  final Map<int, int> colShelfCounts;
  final bool onFloor;
  final String palletCode;
  final String? shelfLabel;
  final int? quantity;
  final String? productName;
  final List<String> localPhotos;
  final String? palletPhotoPath;
  final int? palletPosition;
  final int? palletsOnShelf;
  final Color accent;
  final List<String> allWarehouses;
  final int targetWarehouseIndex;

  const _WarehouseFlythroughScreen({
    required this.warehouseName,
    required this.cols,
    required this.rows,
    this.colShelfCounts = const {},
    required this.targetCol,
    required this.targetRow,
    required this.onFloor,
    required this.palletCode,
    required this.accent,
    this.shelfLabel,
    this.quantity,
    this.productName,
    this.localPhotos = const [],
    this.palletPhotoPath,
    this.palletPosition,
    this.palletsOnShelf,
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
  // 1) ACILIS:      0.00-0.22 (iki raf duvarı merkezden dışa/sola-sağa acılır)
  // 2) KAYDIRMA:    0.22-0.48 (kamera koridorda hedef tarafa ilerler)
  // 3) YAKINLASMA:  0.48-0.72 (hedef sutuna zoom)
  // 4) PALET:       0.72-0.85 (palet etiketi iner + nabiz)
  // 5) FOTOGRAF:    0.85-1.00 (varsa palet fotografi ortaya buyur)
  double get _tIntro => 0.10;
  double get _tOpenEnd => 0.22;
  double get _tPanStart => 0.22;
  double get _tPanEnd => 0.48;
  double get _tZoomStart => 0.48;
  double get _tZoomEnd => 0.72;
  double get _tPalletEnd => 0.85;
  double get _tPhotoEnd => 1.0;
  double get _tInfoStart => 0.70;

  @override
  void initState() {
    super.initState();
    _main = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
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
    if (t < _tOpenEnd) return 'Depo açılıyor…';
    if (t < _tZoomStart) return 'Koridorda ilerleniyor…';
    if (t < _tZoomEnd && !widget.onFloor) {
      return widget.targetCol <= (widget.cols / 2).ceil()
          ? 'Sola dönülüyor…'
          : 'Sağa dönülüyor…';
    }
    if (t < _tZoomEnd) return widget.onFloor ? 'Zemin' : 'Sütun · Raf';
    if (t < _tPalletEnd) return _palletPositionLabel ?? 'Palet bulundu';
    return _hasPalletPhoto ? 'Palet fotoğrafı' : (_palletPositionLabel ?? 'Palet bulundu');
  }

  String? get _palletPositionLabel {
    if (widget.palletPosition == null || widget.palletsOnShelf == null) {
      return null;
    }
    return '${widget.palletPosition}. Palet · ${widget.palletsOnShelf} palet arasında';
  }

  bool get _hasPalletPhoto =>
      widget.palletPhotoPath != null && widget.palletPhotoPath!.isNotEmpty;

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
            final openT = _seg(t, 0.0, _tOpenEnd, Curves.easeOutCubic);
            final pan = _seg(t, _tPanStart, _tPanEnd, Curves.easeInOutCubic);
            final zoom =
                _seg(t, _tZoomStart, _tZoomEnd, Curves.easeInOutCubic);
            final palletIn =
                _seg(t, _tZoomEnd, _tPalletEnd, Curves.easeOutBack);
            final photoReveal =
                _seg(t, _tPalletEnd, _tPhotoEnd, Curves.easeOutCubic);
            final infoIn = _seg(t, _tInfoStart, 1.0, Curves.easeOutCubic);

            return Column(
              children: [
                _header(introIn, pan),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _warehouseFloor(
                              pan, zoom, palletIn, pulse, openT),
                        ),
                        // ── Son asama: paleti ORTAYA al, GERCEK fotografini
                        // buyuterek goster (varsa). Izgaranin ustune biner.
                        if (_hasPalletPhoto && photoReveal > 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: photoReveal.clamp(0.0, 1.0),
                                child: _palletPhotoReveal(photoReveal),
                              ),
                            ),
                          ),
                      ],
                    ),
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
  //  DEPO KORİDORU — GERÇEK "İÇİNE YÜRÜME" SAHNESİ (defter modeli)
  //
  //  Model: bir defteri üçe böl, ORTASINA bastır. Orta şerit = koridor
  //  ZEMİNİ (hep görünür), iki yan şerit = raf DUVARLARI.
  //
  //   1) AÇILIŞ   — duvarlar yere yatık (defter gibi düz) başlar,
  //                 zeminin iki kenarından menteşeli olarak YUKARI
  //                 katlanıp dikilir → koridor oluşur. Tek kaçış
  //                 noktalı (one-point) perspektif: duvarların uzak
  //                 ucu ekranın ortasına doğru daralır.
  //   2) YÜRÜYÜŞ  — kamera koridorun İÇİNE ilerler: sütunlar
  //                 derinlikten üzerimize doğru akar, hedef sütun
  //                 yaklaşınca durulur. Palet hangi taraftaysa o duvar
  //                 parlar, diğeri sönükleşir.
  //   3) DÖNÜŞ    — kamera hedef duvara döner: hedef duvar düzleşip
  //                 yüzümüze bakar, raf izgarası netleşir, hedef raf
  //                 vurgulanır.
  //   4) PALET    — palet etiketi iner (kaçıncı palet olduğu yazar).
  //   5) FOTOĞRAF — paletin gerçek fotoğrafı büyüyerek gösterilir.
  // ════════════════════════════════════════════════════════════════
  Widget _warehouseFloor(
      double pan, double zoom, double palletIn, double pulse, double openT) {
    final leftCount = (widget.cols / 2).ceil().clamp(1, widget.cols);
    final rightCount = (widget.cols - leftCount).clamp(0, widget.cols);
    final targetIsLeft = widget.targetCol <= leftCount;
    final targetLocalCol =
        targetIsLeft ? widget.targetCol : widget.targetCol - leftCount;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Container(
        color:
            AppTheme.isLight ? AppTheme.surfaceAlt : const Color(0xFF0E1015),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight.isFinite ? c.maxHeight : 360.0;
            // Duvar genişliği: ekranın yarısından biraz fazla; perspektif
            // dönüşü sonrası koridor ortada belirgin kalır.
            final wallW = w * 0.56;

            return Stack(
              children: [
                // ── KORİDOR ZEMİNİ (defterin ortası): trapez perspektif.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CorridorFloorPainter(
                        openT: openT,
                        walk: pan,
                        accent: widget.accent,
                        isLight: AppTheme.isLight,
                      ),
                    ),
                  ),
                ),
                // ── SOL DUVAR ─ zeminin sol kenarından menteşeli kalkar.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: wallW,
                  child: _wall(
                    isLeftSide: true,
                    colCount: leftCount,
                    colOffset: 0,
                    openT: openT,
                    isTargetWall: targetIsLeft,
                    targetLocalCol: targetIsLeft ? targetLocalCol : null,
                    walk: pan,
                    zoom: zoom,
                    palletIn: palletIn,
                    pulse: pulse,
                    sceneH: h,
                  ),
                ),
                // ── SAĞ DUVAR ─ zeminin sağ kenarından menteşeli kalkar.
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: wallW,
                  child: _wall(
                    isLeftSide: false,
                    colCount: rightCount,
                    colOffset: leftCount,
                    openT: openT,
                    isTargetWall: !targetIsLeft,
                    targetLocalCol: !targetIsLeft ? targetLocalCol : null,
                    walk: pan,
                    zoom: zoom,
                    palletIn: palletIn,
                    pulse: pulse,
                    sceneH: h,
                  ),
                ),
                // Uzak uç sisi: koridorun dibi karanlığa/derinliğe gider.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (openT * (1 - zoom)).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 0.9,
                            colors: [
                              Colors.black.withOpacity(0.35),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.45],
                          ),
                        ),
                      ),
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

  /// Tek raf duvarı. İki dönüşüm katmanı:
  ///  * DIŞ Transform — perspektif + rotateY: AÇILIŞTA duvar yatıktan
  ///    (defter sayfası gibi, açı ~88°) dikeye kalkar; dururken hafif
  ///    açıyla (one-point perspektif) koridorun dibine daralır. DÖNÜŞTE
  ///    hedef duvar açısı sıfıra iner (yüzümüze düzleşir).
  ///  * İÇ Transform.translate — YÜRÜYÜŞ: sütun şeridi yakın kenara
  ///    doğru kaydırılır; perspektif sayesinde uzaktaki sütunlar
  ///    büyüyerek "üzerimize akar" — koridorda ilerleme hissi.
  Widget _wall({
    required bool isLeftSide,
    required int colCount,
    required int colOffset, // bu duvarin ilk sutununun GLOBAL sutun no'su - 1
    required double openT,
    required bool isTargetWall,
    int? targetLocalCol,
    required double walk, // 0..1 koridorda ilerleme
    required double zoom, // 0..1 hedef duvara donus
    required double palletIn,
    required double pulse,
    required double sceneH,
  }) {
    if (colCount <= 0) return const SizedBox.shrink();
    final acc = widget.accent;

    // ── AÇILIŞ: yatık (1.52 ≈ yere serili) -> koridor duruşu (0.62).
    const lyingAngle = 1.52; // ~87°: sayfa yerde
    const corridorAngle = 0.62; // dururken: uzak uç merkeze daralır
    double angle = lyingAngle + (corridorAngle - lyingAngle) * openT;

    // ── DÖNÜŞ: hedef duvar düzleşir (0'a), diğeri daha da yan döner.
    if (isTargetWall) {
      angle *= (1.0 - zoom * 0.92);
    } else {
      angle += (1.35 - angle) * zoom * 0.7;
    }

    final dim = isTargetWall
        ? 1.0
        : (1.0 - walk * 0.35 - zoom * 0.35).clamp(0.22, 1.0);

    return Opacity(
      opacity: (openT * 1.4).clamp(0.0, 1.0) * dim,
      child: Transform(
        // Menteşe: koridora bakan İÇ kenar değil, sahne kenarı — yakın
        // kenar sabit kalır, uzak uç merkeze daralır (one-point).
        alignment:
            isLeftSide ? Alignment.centerLeft : Alignment.centerRight,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0020)
          ..rotateY(isLeftSide ? angle : -angle),
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 5.0;
              final cW = c.maxWidth; // gorunur pencere genisligi
              final cellW =
                  ((cW - gap * (colCount + 1)) / colCount).clamp(26.0, 96.0);
              final stripRaw = cellW * colCount + gap * (colCount + 1);
              final stripW = stripRaw < cW ? cW : stripRaw; // serit genisligi
              final gridH = c.maxHeight.isFinite ? c.maxHeight : sceneH;

              // Derinlik sirasi: 1. sutun YAKIN kenarda. Sol duvarda yakin
              // kenar SOL, sag duvarda SAG oldugu icin sag duvar AYNALANIR.
              double colX(int col) => isLeftSide
                  ? gap + col * (cellW + gap)
                  : stripW - (gap + col * (cellW + gap)) - cellW;

              // ── YÜRÜYÜŞ: hedef sutun yuruyus sonunda yakin kenara
              // (pencerenin %30 icerisine) gelir; hedef bu duvarda degilse
              // sutunlar hafif paralaksla yanindan akip gecer.
              final base = isLeftSide ? 0.0 : stripW - cW;
              double travel;
              if (isTargetWall && targetLocalCol != null) {
                final targetCenter =
                    colX(targetLocalCol - 1) + cellW / 2;
                final wanted = cW * (isLeftSide ? 0.30 : 0.70);
                travel = (wanted + base - targetCenter) * walk;
              } else {
                travel = (isLeftSide ? -1 : 1) * walk * cellW * 1.3;
              }

              // Hedef sutunun raf sayısı → palet chip dikey konumu.
              double chipTop = 0;
              if (isTargetWall && targetLocalCol != null) {
                final nT =
                    (widget.colShelfCounts[colOffset + targetLocalCol] ??
                            widget.rows)
                        .clamp(1, widget.rows);
                final bandHT =
                    ((gridH - gap * (nT + 1)) / nT).clamp(5.0, gridH);
                chipTop = gap + (nT - widget.targetRow) * (bandHT + gap);
              }

              return Container(
                color: AppTheme.isLight
                    ? AppTheme.hairline.withOpacity(0.25)
                    : Colors.white.withOpacity(0.035),
                child: OverflowBox(
                  maxWidth: stripW,
                  alignment: isLeftSide
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Transform.translate(
                    offset: Offset(travel, 0),
                    child: SizedBox(
                      width: stripW,
                      height: gridH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (var col = 0; col < colCount; col++)
                            for (var sh = 1;
                                sh <=
                                    (widget.colShelfCounts[
                                                colOffset + col + 1] ??
                                            widget.rows)
                                        .clamp(1, widget.rows);
                                sh++)
                              _cell(
                                  col,
                                  colX(col),
                                  sh,
                                  (widget.colShelfCounts[
                                              colOffset + col + 1] ??
                                          widget.rows)
                                      .clamp(1, widget.rows),
                                  cellW,
                                  gridH,
                                  gap,
                                  acc,
                                  walk,
                                  zoom,
                                  isTargetWall,
                                  targetLocalCol),
                          if (isTargetWall && targetLocalCol != null)
                            Positioned(
                              left: colX(targetLocalCol - 1) +
                                  cellW / 2 -
                                  46,
                              top: chipTop - 40 - (1 - palletIn) * 30,
                              child: Opacity(
                                opacity: palletIn.clamp(0.0, 1.0),
                                child: _palletChip(acc, pulse),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cell(
      int col,
      double x, // seritteki yatay konum (aynalama uygulanmis)
      int shelfNo, // 1 = EN ALT raf
      int shelfCount, // bu sutunun GERCEK raf sayisi
      double cellW,
      double fullH, // sutunun TAM yuksekligi (tum sutunlar icin ayni)
      double gap,
      Color acc,
      double focusT,
      double zoom,
      bool isTargetWall,
      int? targetLocalCol) {
    // Sutunun tam yuksekligi kendi raf sayisina bolunur: raf boyu degisken.
    final n = shelfCount < 1 ? 1 : shelfCount;
    final bandH = ((fullH - gap * (n + 1)) / n).clamp(5.0, fullH);
    final top = gap + (n - shelfNo) * (bandH + gap); // raf 1 en altta

    final isTargetCol = isTargetWall && targetLocalCol == (col + 1);
    final isTarget = isTargetCol && shelfNo == widget.targetRow;
    final colHighlight = isTargetCol ? (0.5 + 0.5 * focusT) : 0.0;
    final dim = isTarget
        ? 1.0
        : (isTargetCol
            ? (1.0 - zoom * 0.25).clamp(0.55, 1.0)
            : (1.0 - zoom * 0.65).clamp(0.28, 1.0));

    return Positioned(
      left: x,
      top: top,
      width: cellW,
      height: bandH,
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

  Widget _palletPhotoReveal(double p) {
    final acc = widget.accent;
    // 0.85 -> 1.0 olceklenerek buyur, arka planı hafifçe karart.
    final scale = 0.82 + p * 0.18;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Izgarayi hafifce karart ki foto one cıksin.
        Container(color: Colors.black.withOpacity(0.45 * p)),
        Transform.scale(
          scale: scale,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(color: acc, width: 2),
              boxShadow: AppTheme.glow(acc),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rSm),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.file(
                  File(widget.palletPhotoPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.surfaceAlt,
                    child: Icon(Icons.inventory_2_rounded,
                        size: 40, color: AppTheme.textTertiary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _palletChip(Color acc, double pulse) {
    final posLabel = widget.palletPosition != null
        ? '${widget.palletPosition}.'
        : null;
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
            posLabel != null
                ? '$posLabel Palet · ${widget.palletCode}'
                : widget.palletCode,
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
                    if (_palletPositionLabel != null)
                      Text(
                        _palletPositionLabel!,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary),
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


/// Koridor ZEMINI — defterin ortası. Tek kaçış noktalı perspektifte
/// trapez zemin çizer; YÜRÜYÜŞ sırasında enine çizgiler izleyiciye
/// doğru akarak ilerleme hissini güçlendirir.
class _CorridorFloorPainter extends CustomPainter {
  final double openT; // duvarlar kalkarken zemin belirir
  final double walk; // 0..1 ilerleme — cizgiler akar
  final Color accent;
  final bool isLight;
  _CorridorFloorPainter({
    required this.openT,
    required this.walk,
    required this.accent,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (openT <= 0) return;
    final w = size.width, h = size.height;
    final vp = Offset(w / 2, h * 0.42); // kaçış noktası
    // Zemin: yakın kenar tüm alt genişlik, uzak kenar kaçış noktasında dar.
    final nearHalf = w * 0.30 * openT; // yakın yarı genişlik
    final farHalf = w * 0.03;
    final nearY = h;
    final farY = vp.dy + (h - vp.dy) * 0.12;

    final floor = Path()
      ..moveTo(w / 2 - nearHalf, nearY)
      ..lineTo(w / 2 - farHalf, farY)
      ..lineTo(w / 2 + farHalf, farY)
      ..lineTo(w / 2 + nearHalf, nearY)
      ..close();
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: isLight
            ? [const Color(0xFFD8DBE2), const Color(0xFFB9BDC7)]
            : [const Color(0xFF23262E), const Color(0xFF12141A)],
      ).createShader(Rect.fromLTWH(0, farY, w, nearY - farY));
    canvas.drawPath(floor, basePaint);

    // Kenar şeritleri (sarı depo çizgisi hissi).
    final edge = Paint()
      ..color = accent.withOpacity(0.55 * openT)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(w / 2 - nearHalf, nearY), Offset(w / 2 - farHalf, farY), edge);
    canvas.drawLine(
        Offset(w / 2 + nearHalf, nearY), Offset(w / 2 + farHalf, farY), edge);

    // Enine akış çizgileri: perspektif aralıklı; walk ile yakına akar.
    final line = Paint()
      ..color = (isLight ? Colors.black : Colors.white)
          .withOpacity(0.10 * openT)
      ..strokeWidth = 1.4;
    const nLines = 7;
    for (int i = 0; i < nLines; i++) {
      // 0..1 derinlik parametresi; walk kayması mod 1 ile döngü.
      final d = ((i / nLines) + walk * 1.6) % 1.0;
      // Perspektif: derinlik d=0 uzak, d=1 yakın; kare hızlanma.
      final tY = farY + (nearY - farY) * (d * d);
      final half = farHalf + (nearHalf - farHalf) * (d * d);
      canvas.drawLine(
          Offset(w / 2 - half, tY), Offset(w / 2 + half, tY), line);
    }
  }

  @override
  bool shouldRepaint(_CorridorFloorPainter old) =>
      old.openT != openT ||
      old.walk != walk ||
      old.accent != accent ||
      old.isLight != isLight;
}
