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
    if (t < _tZoomStart) {
      return widget.onFloor
          ? 'Zemine gidiliyor…'
          : (widget.targetCol <= (widget.cols / 2)
              ? 'Sol tarafa geçiliyor…'
              : 'Sağ tarafa geçiliyor…');
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
  //  DEPO KORİDORU (3B hissi) — sütunlar SOLDA ve SAĞDA iki rafa
  //  bölünür (6 sütun varsa 3'ü sol, 3'ü sağ), tıpkı gerçek bir
  //  koridorda karşılıklı raflar gibi. Perspektif eğim (rotateY) ile
  //  duvarlar hafifçe içbükey görünür.
  //
  //   AÇILIŞ   — duvarlar merkezde kapalı başlar, dışa (sola/sağa)
  //              açılarak koridoru ortaya çıkarır.
  //   KAYDIRMA — hedef tarafın duvarı kameraya döner/büyür/parlar,
  //              diğer taraf hafifçe arkaya döner/sönükleşir.
  //   YAKINLAŞMA/PALET/FOTOĞRAF — hedef duvar üstünde aynen önceki
  //              gibi devam eder.
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
        color: AppTheme.isLight ? AppTheme.surfaceAlt : const Color(0xFF14161C),
        child: LayoutBuilder(
          builder: (context, c) {
            final wallW = c.maxWidth * 0.47;
            return Stack(
              children: [
                // Koridor zemini: hafif isik/gradyan ile derinlik hissi.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.18),
                            Colors.transparent,
                            Colors.black.withOpacity(0.10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
                    focusT: pan,
                    zoom: zoom,
                    palletIn: palletIn,
                    pulse: pulse,
                  ),
                ),
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
                    focusT: pan,
                    zoom: zoom,
                    palletIn: palletIn,
                    pulse: pulse,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Tek bir raf duvarı (sol veya sağ). Perspektif için Matrix4 +
  /// rotateY kullanılır: duvar, iç kenarından (koridor ortasından)
  /// menteşeliymiş gibi açılır/kapanır.
  Widget _wall({
    required bool isLeftSide,
    required int colCount,
    required int colOffset, // bu duvarin ilk sutununun GLOBAL sutun no'su - 1
    required double openT,
    required bool isTargetWall,
    int? targetLocalCol,
    required double focusT,
    required double zoom,
    required double palletIn,
    required double pulse,
  }) {
    if (colCount <= 0) return const SizedBox.shrink();
    final acc = widget.accent;

    // AÇILIŞ: kapaliyken duvar kenardan gorunur (buyuk aci = ~kenara
    // yaslanmis), acildikca dinlenme egimine gelir (hafif ic-buk).
    const closedAngle = 1.45;
    const restAngle = 0.5;
    double angle = closedAngle + (restAngle - closedAngle) * openT;
    // KAYDIRMA: hedef duvar kameraya donuk hale gelir (aci kuculur,
    // adeta yuzumuze doner); diger duvar hafifce arkaya kacar.
    if (isTargetWall) {
      angle -= angle * focusT * 0.85;
    } else {
      angle += (1.25 - angle) * focusT * 0.55;
    }
    final dim = isTargetWall ? 1.0 : (1.0 - focusT * 0.55).clamp(0.32, 1.0);
    final scale = isTargetWall ? (1.0 + zoom * 0.12) : 1.0;

    return Opacity(
      opacity: openT.clamp(0.0, 1.0) * dim,
      child: Transform(
        alignment: isLeftSide ? Alignment.centerRight : Alignment.centerLeft,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateY(isLeftSide ? angle : -angle)
          ..scale(scale),
        child: LayoutBuilder(
          builder: (context, c) {
            const gap = 5.0;
            final cellW = ((c.maxWidth - gap * (colCount + 1)) / colCount)
                .clamp(20.0, 74.0);
            final gridW = cellW * colCount + gap * (colCount + 1);
            // TUM SUTUNLAR AYNI TOPLAM YUKSEKLIK: rafin dik direkleri aynı
            // boydadır. Her sutun bu yuksekligi KENDI gercek raf sayisina
            // boler; dolayisiyla raf yukseklikleri sutundan sutuna DEGISIR
            // (3 rafli sutun = 3 yuksek raf, 6 rafli = 6 kisa raf).
            final gridH = c.maxHeight.isFinite ? c.maxHeight : 300.0;

            // Hedef sutunun kendi rafina gore palet chip konumu.
            double chipTop = 0;
            if (isTargetWall && targetLocalCol != null) {
              final nT = (widget.colShelfCounts[colOffset + targetLocalCol] ??
                      widget.rows)
                  .clamp(1, widget.rows);
              final bandHT = ((gridH - gap * (nT + 1)) / nT).clamp(5.0, gridH);
              chipTop = gap + (nT - widget.targetRow) * (bandHT + gap);
            }

            return Container(
              color: AppTheme.isLight
                  ? AppTheme.hairline.withOpacity(0.25)
                  : Colors.white.withOpacity(0.03),
              child: Center(
                child: SizedBox(
                  width: gridW,
                  height: gridH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Her sutun ayni toplam yukseklikte; kendi GERCEK raf
                      // sayisina bolunur. Raf 1 = EN ALT.
                      for (var col = 0; col < colCount; col++)
                        for (var s = 1;
                            s <=
                                (widget.colShelfCounts[colOffset + col + 1] ??
                                        widget.rows)
                                    .clamp(1, widget.rows);
                            s++)
                          _cell(
                              col,
                              s,
                              (widget.colShelfCounts[colOffset + col + 1] ??
                                      widget.rows)
                                  .clamp(1, widget.rows),
                              cellW,
                              gridH,
                              gap,
                              acc,
                              focusT,
                              zoom,
                              isTargetWall,
                              targetLocalCol),
                      if (isTargetWall && targetLocalCol != null)
                        Positioned(
                          left: gap +
                              (targetLocalCol - 1) * (cellW + gap) +
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
            );
          },
        ),
      ),
    );
  }

  Widget _cell(
      int col,
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
      left: gap + col * (cellW + gap),
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
