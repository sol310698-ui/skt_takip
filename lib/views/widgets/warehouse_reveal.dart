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
  // YENI AKIS (tarifе gore):
  //  1) KORIDOR    0.00-0.22  ortada bosluk; sol/sag depo duvarlari
  //                            perspektifle karsiya dogru daralir.
  //  2) DUZLESME   0.22-0.46  hedef taraf (sol ise sol) 90 dereceye
  //                            donup KARSI DUZLEME dumduz gelir; diger
  //                            taraf kayip gider.
  //  3) IZOLASYON  0.46-0.66  hedef sutun tek basina kalir ve genisler
  //                            (digerleri solup daralir).
  //  4) RAF        0.66-0.82  hedef raf vurgulanir + palet etiketi iner.
  //  5) FOTOGRAF   0.82-1.00  paletin gercek fotografi buyuyerek gelir.
  double get _tIntro => 0.08;
  double get _tOpenEnd => 0.22;
  double get _tFlatStart => 0.22;
  double get _tFlatEnd => 0.46;
  double get _tIsoStart => 0.46;
  double get _tIsoEnd => 0.66;
  double get _tShelfStart => 0.66;
  double get _tShelfEnd => 0.82;
  double get _tPhotoEnd => 1.0;
  double get _tInfoStart => 0.72;

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
    if (!_landedHaptic && _main.value >= _tShelfEnd) {
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
    if (t < _tOpenEnd) return 'Koridora bakılıyor…';
    if (t < _tFlatEnd && !widget.onFloor) {
      return widget.targetCol <= (widget.cols / 2).ceil()
          ? 'Sol depoya dönülüyor…'
          : 'Sağ depoya dönülüyor…';
    }
    if (t < _tFlatEnd) return 'Zemine gidiliyor…';
    if (t < _tIsoEnd) return 'Sütun ${widget.targetCol} bulunuyor…';
    if (t < _tShelfEnd) return _palletPositionLabel ?? 'Raf ${widget.targetRow}';
    return _hasPalletPhoto
        ? 'Palet fotoğrafı'
        : (_palletPositionLabel ?? 'Palet bulundu');
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
            // flat: hedef tarafi 90 dereceye dondurup yuze getirir.
            final flat = _seg(t, _tFlatStart, _tFlatEnd, Curves.easeInOutCubic);
            // iso: hedef sutunu tek basina birakip genisletir.
            final iso = _seg(t, _tIsoStart, _tIsoEnd, Curves.easeInOutCubic);
            // shelf: hedef rafi vurgular + palet etiketi iner.
            final shelfT =
                _seg(t, _tShelfStart, _tShelfEnd, Curves.easeOutBack);
            final photoReveal =
                _seg(t, _tShelfEnd, _tPhotoEnd, Curves.easeOutCubic);
            final infoIn = _seg(t, _tInfoStart, 1.0, Curves.easeOutCubic);

            return Column(
              children: [
                _header(introIn, flat),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _warehouseFloor(
                              openT, flat, iso, shelfT, pulse),
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
  //  DEPO KORİDORU — perspektif koridor + hedef tarafı düzleştirme
  //
  //  Model: ekranın ORTASINDA bir geçit/boşluk; SOLDA sol depo duvarı,
  //  SAĞDA sağ depo duvarı. Her duvar perspektifle karşıya (merkeze)
  //  daralır — koridora bakıyormuş hissi.
  //
  //   1) KORİDOR    — iki depo duvarı perspektifle görünür, ortada boşluk.
  //   2) DÜZLEŞME   — hedef sütun toplam/2'ye göre solda mı sağda mı; o
  //                   tarafın duvarı 90°'ye dönüp KARŞI DÜZLEME dümdüz
  //                   gelir (yüze bakar), diğer taraf kayıp gider.
  //   3) İZOLASYON  — hedef sütun tek başına kalıp GENİŞLER, diğerleri
  //                   0'a daralıp solar.
  //   4) RAF        — hedef raf vurgulanır + palet etiketi iner.
  //   5) FOTOĞRAF   — paletin gerçek fotoğrafı büyüyerek gösterilir.
  // ════════════════════════════════════════════════════════════════
  Widget _warehouseFloor(
      double openT, double flat, double iso, double shelfT, double pulse) {
    // Sutunlari iki depoya bol: sol yariya sol depo, sag yariya sag depo.
    final leftCount = (widget.cols / 2).ceil().clamp(1, widget.cols);
    final rightCount = (widget.cols - leftCount).clamp(0, widget.cols);
    final targetIsLeft = widget.targetCol <= leftCount;
    // Hedef sutunun kendi duvarindaki yerel (1-based) indeksi.
    final targetLocalCol =
        targetIsLeft ? widget.targetCol : widget.targetCol - leftCount;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: Container(
        color:
            AppTheme.isLight ? AppTheme.surfaceAlt : const Color(0xFF0B0D12),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight.isFinite ? c.maxHeight : 360.0;

            return Stack(
              children: [
                // ── KORIDOR ZEMINI: ortada bosluk, karsiya daralir. ──
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CorridorPainter(
                        openT: openT,
                        flat: flat,
                        targetIsLeft: targetIsLeft,
                        accent: widget.accent,
                        isLight: AppTheme.isLight,
                      ),
                    ),
                  ),
                ),

                // ── SOL DEPO DUVARI ──
                if (leftCount > 0)
                  _sideWall(
                    isLeftSide: true,
                    colCount: leftCount,
                    colOffset: 0,
                    isTarget: targetIsLeft,
                    targetLocalCol: targetIsLeft ? targetLocalCol : null,
                    sceneW: w,
                    sceneH: h,
                    openT: openT,
                    flat: flat,
                    iso: iso,
                    shelfT: shelfT,
                    pulse: pulse,
                  ),

                // ── SAG DEPO DUVARI ──
                if (rightCount > 0)
                  _sideWall(
                    isLeftSide: false,
                    colCount: rightCount,
                    colOffset: leftCount,
                    isTarget: !targetIsLeft,
                    targetLocalCol: !targetIsLeft ? targetLocalCol : null,
                    sceneW: w,
                    sceneH: h,
                    openT: openT,
                    flat: flat,
                    iso: iso,
                    shelfT: shelfT,
                    pulse: pulse,
                  ),

                // Uzak uc karartmasi (koridor derinlik hissi); duzlesince kalkar.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (openT * (1 - flat) * 0.9).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -0.15),
                            radius: 0.85,
                            colors: [
                              Colors.black.withOpacity(0.40),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.5],
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

  /// Bir depo duvari (sol ya da sag). Uc asamayi tek Transform zinciriyle
  /// yonetir:
  ///   * KORIDOR (openT): duvar perspektifle yana yatik durur; yakin kenar
  ///     ortadaki boslukta, uzak kenar karsiya (merkeze) daralir.
  ///   * DUZLESME (flat): SADECE hedef duvarda rotateY 0'a iner → duvar
  ///     yuze donup KARSI DUZLEME dumduz gelir (90°'lik bakis). Hedef
  ///     olmayan duvar ekrandan disari kayip silinir.
  ///   * IZOLASYON (iso) + RAF (shelfT): _cell icinde; hedef sutun genisler,
  ///     digerleri solar; hedef raf vurgulanir.
  Widget _sideWall({
    required bool isLeftSide,
    required int colCount,
    required int colOffset,
    required bool isTarget,
    int? targetLocalCol,
    required double sceneW,
    required double sceneH,
    required double openT,
    required double flat,
    required double iso,
    required double shelfT,
    required double pulse,
  }) {
    if (colCount <= 0) return const SizedBox.shrink();

    // Koridor duruşu: her duvar sahne yarisini kaplar, ortada ~%12 bosluk.
    final gapHalf = sceneW * 0.06;
    final wallW = sceneW * 0.5 - gapHalf;

    // KORIDOR açisi: yana yatik (~0.95 rad). Yakin kenar boslukta, uzak
    // kenar merkeze daralir → sol duvar saga, sag duvar sola bakar.
    const corridorAngle = 0.95;

    // DUZLESME: hedef duvar 90°'ye (rotateY 0) gelir. Hedef olmayan duvar
    // daha da yan donup kayar.
    double angle;
    double offsetX;
    double opacity;
    if (isTarget) {
      angle = corridorAngle * (1 - flat); // 0.95 → 0 (yuze donuk)
      // Yaklastikca duvar sahnenin ortasina kayar ve genisler.
      final startX = isLeftSide ? -gapHalf : gapHalf; // koridordaki yeri
      offsetX = startX * (1 - flat);
      opacity = openT.clamp(0.0, 1.0);
    } else {
      angle = corridorAngle + (1.4 - corridorAngle) * flat; // daha da yan
      // Hedef olmayan duvar kenara kayip silinir.
      offsetX = (isLeftSide ? -1 : 1) * sceneW * 0.5 * flat;
      opacity = (openT * (1 - flat)).clamp(0.0, 1.0);
    }

    // Duvar, duzlestikce koridor yarisindan → neredeyse tam sahne genisligine.
    final curW = wallW + (sceneW - wallW) * (isTarget ? flat : 0.0);
    // Sol duvar sahnenin solunda, sag duvar saginda konumlanir; hedef duvar
    // duzlestikce ortaya toplanir.
    final leftPos = isLeftSide
        ? 0.0 + offsetX
        : sceneW - curW + offsetX;

    return Positioned(
      left: leftPos,
      top: 0,
      bottom: 0,
      width: curW,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment:
              isLeftSide ? Alignment.centerRight : Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateY(isLeftSide ? angle : -angle),
          child: _wallGrid(
            isLeftSide: isLeftSide,
            colCount: colCount,
            colOffset: colOffset,
            isTargetWall: isTarget,
            targetLocalCol: targetLocalCol,
            iso: iso,
            shelfT: shelfT,
            flat: flat,
            pulse: pulse,
          ),
        ),
      ),
    );
  }

  /// Duvarin raf izgarasi. Sutunlar yatayda dizilir; IZOLASYON asamasinda
  /// hedef sutun tum genisligi kaplayacak sekilde BUYUR, digerleri 0'a
  /// dogru daralip solar.
  Widget _wallGrid({
    required bool isLeftSide,
    required int colCount,
    required int colOffset,
    required bool isTargetWall,
    int? targetLocalCol,
    required double iso,
    required double shelfT,
    required double flat,
    required double pulse,
  }) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = 6.0;
          final gridH = c.maxHeight.isFinite ? c.maxHeight : 300.0;
          final fullW = c.maxWidth;

          // Her sutunun IZOLASYON genisligi. Hedef sutun 1'e, digerleri
          // 0'a gider. iso=0 iken hepsi esit (1/colCount).
          double weight(int localCol) {
            final even = 1.0 / colCount;
            if (!isTargetWall || targetLocalCol == null) return even;
            final isT = localCol == targetLocalCol;
            final target = isT ? 1.0 : 0.0;
            return even + (target - even) * iso;
          }

          // Sol kenardan kumulatif yerlesim (agirliklara gore).
          final totalGap = gap * (colCount + 1);
          final usableW = (fullW - totalGap).clamp(0.0, fullW);

          double cursor = gap;
          final positions = <({double x, double w, int local})>[];
          for (int i = 0; i < colCount; i++) {
            final local = i + 1;
            final cw = usableW * weight(local);
            positions.add((x: cursor, w: cw, local: local));
            cursor += cw + gap;
          }

          return SizedBox(
            width: fullW,
            height: gridH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final p in positions)
                  ..._buildColumn(
                    localCol: p.local,
                    x: p.x,
                    colW: p.w,
                    gridH: gridH,
                    gap: gap,
                    colOffset: colOffset,
                    isTargetWall: isTargetWall,
                    targetLocalCol: targetLocalCol,
                    iso: iso,
                    shelfT: shelfT,
                    pulse: pulse,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Tek sutunun raflari + (hedefse) palet etiketi.
  List<Widget> _buildColumn({
    required int localCol,
    required double x,
    required double colW,
    required double gridH,
    required double gap,
    required int colOffset,
    required bool isTargetWall,
    int? targetLocalCol,
    required double iso,
    required double shelfT,
    required double pulse,
  }) {
    final acc = widget.accent;
    final isTargetCol = isTargetWall && targetLocalCol == localCol;
    // Hedef olmayan sutunlar izolasyonda solar.
    final colOpacity =
        isTargetCol ? 1.0 : (1.0 - iso * 0.85).clamp(0.0, 1.0);
    if (colW <= 1) return const [];

    final n = (widget.colShelfCounts[colOffset + localCol] ?? widget.rows)
        .clamp(1, widget.rows);
    final bandH = ((gridH - gap * (n + 1)) / n).clamp(4.0, gridH);

    final cells = <Widget>[];
    for (int sh = 1; sh <= n; sh++) {
      final top = gap + (n - sh) * (bandH + gap); // raf 1 en altta
      final isTarget = isTargetCol && sh == widget.targetRow;
      // Hedef raf, RAF asamasinda parlar; hedef sutundaki digerleri soluk.
      final cellFill = isTarget
          ? Color.lerp(acc.withOpacity(0.5), acc, shelfT)!
          : Color.lerp(
              AppTheme.hairline,
              acc.withOpacity(0.30),
              isTargetCol ? iso * 0.6 : 0.0,
            )!;
      cells.add(Positioned(
        left: x,
        top: top,
        width: colW,
        height: bandH,
        child: Opacity(
          opacity: isTargetCol
              ? 1.0
              : colOpacity,
          child: Container(
            decoration: BoxDecoration(
              color: cellFill,
              borderRadius: BorderRadius.circular(4),
              border: isTarget
                  ? Border.all(
                      color: Colors.white.withOpacity(0.9),
                      width: 1.6 + pulse * 0.8)
                  : null,
              boxShadow: isTarget ? AppTheme.glow(acc) : null,
            ),
          ),
        ),
      ));
    }

    // Palet etiketi: hedef sutun + hedef raf uzerine, RAF asamasinda iner.
    if (isTargetCol && shelfT > 0) {
      final targetTop = gap + (n - widget.targetRow) * (bandH + gap);
      cells.add(Positioned(
        left: x + colW / 2 - 60,
        width: 120,
        top: (targetTop - 42 - (1 - shelfT) * 26).clamp(0.0, gridH),
        child: Opacity(
          opacity: shelfT.clamp(0.0, 1.0),
          child: Center(child: _palletChip(acc, pulse)),
        ),
      ));
    }

    return cells;
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


/// Koridor ZEMINI — ortada bir GECIT/bosluk, iki yanda depo tabani.
/// Tek kacis noktali perspektifle karsiya daralir. DUZLESME (flat)
/// asamasinda zemin duz bir tabana donusup solar.
class _CorridorPainter extends CustomPainter {
  final double openT; // koridor belirir
  final double flat; // 0..1 hedef tarafa donus (zemin solar)
  final bool targetIsLeft;
  final Color accent;
  final bool isLight;
  _CorridorPainter({
    required this.openT,
    required this.flat,
    required this.targetIsLeft,
    required this.accent,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (openT <= 0) return;
    final w = size.width, h = size.height;
    final vis = openT * (1 - flat * 0.9); // duzlesince kaybol
    if (vis <= 0.02) return;

    // Kacis noktasi ust-orta.
    final vpY = h * 0.30;
    // Koridor GECIDI: yakin uc genis, uzak uc kacis noktasinda dar.
    final nearHalf = w * 0.14; // ortadaki boslugun yakin yari genisligi
    final farHalf = w * 0.015;
    final nearY = h;
    final farY = vpY + (h - vpY) * 0.06;

    // Gecit zemini (koyu, parlak kenarli).
    final aisle = Path()
      ..moveTo(w / 2 - nearHalf, nearY)
      ..lineTo(w / 2 - farHalf, farY)
      ..lineTo(w / 2 + farHalf, farY)
      ..lineTo(w / 2 + nearHalf, nearY)
      ..close();
    canvas.drawPath(
      aisle,
      Paint()
        ..color = (isLight ? const Color(0xFFB9BDC7) : const Color(0xFF171A22))
            .withOpacity(vis),
    );

    // Gecit kenar cizgileri (sari depo seridi).
    final edge = Paint()
      ..color = accent.withOpacity(0.6 * vis)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(w / 2 - nearHalf, nearY), Offset(w / 2 - farHalf, farY), edge);
    canvas.drawLine(
        Offset(w / 2 + nearHalf, nearY), Offset(w / 2 + farHalf, farY), edge);

    // Enine zemin cizgileri (derinlik/mesafe hissi).
    final line = Paint()
      ..color = (isLight ? Colors.black : Colors.white).withOpacity(0.10 * vis)
      ..strokeWidth = 1.2;
    const nLines = 6;
    for (int i = 1; i <= nLines; i++) {
      final d = i / (nLines + 1);
      final tY = farY + (nearY - farY) * (d * d);
      final half = farHalf + (nearHalf - farHalf) * (d * d);
      canvas.drawLine(
          Offset(w / 2 - half, tY), Offset(w / 2 + half, tY), line);
    }

    // Hedef taraf yon oku: koridorda hangi depoya gidilecegini isaret eder.
    if (openT > 0.6 && flat < 0.5) {
      final arrowPaint = Paint()
        ..color = accent.withOpacity((0.8 * (1 - flat)).clamp(0.0, 1.0));
      final cx = targetIsLeft ? w * 0.30 : w * 0.70;
      final cy = h * 0.5;
      final dir = targetIsLeft ? -1.0 : 1.0;
      final path = Path()
        ..moveTo(cx - 14 * dir, cy - 16)
        ..lineTo(cx + 10 * dir, cy)
        ..lineTo(cx - 14 * dir, cy + 16);
      canvas.drawPath(
          path,
          arrowPaint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(_CorridorPainter old) =>
      old.openT != openT ||
      old.flat != flat ||
      old.targetIsLeft != targetIsLeft ||
      old.accent != accent ||
      old.isLight != isLight;
}
