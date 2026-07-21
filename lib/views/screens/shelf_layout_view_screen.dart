import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/services/database_service.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/models/barcode_entry.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
import 'shelf_scan_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYON DIZILIM — GERCEKCI 3D RAF VITRINI (v4 — bastan tasarim)
/// ────────────────────────────────────────────────────────────────────
///  Magazadaki gibi DERINLIKLI, fotografli bir vitrin:
///   - HERO: reyon adi + sutun/raf/urun ozeti + kapak fotografi.
///   - SUTUN SEKMELERI: cok sutunlu reyonda ustte segment; secili sutunun
///     "dolabi" tek ekranda gosterilir (yatayda kayma yok, net odak).
///   - DOLAP: perspektifli arka panel + ust uste GERCEK RAF TAHTALARI.
///     Her tahta one dogru hafif egimli (3D), on kenari kalin+golgeli;
///     urunler tahtanin USTUNDE, dibe dogru hafif buyuyerek "duruyor".
///   - Urun karosu: fotograf + zemin golgesi (yere basma hissi), adet
///     rozeti; uzun basinca hizli sil, dokununca detay penceresi.
///   - Her rafta "+" ile hizli urun ekle; sutun sonunda "Raf ekle".
/// ════════════════════════════════════════════════════════════════════
class ShelfLayoutViewScreen extends StatefulWidget {
  final int unitId;
  const ShelfLayoutViewScreen({super.key, required this.unitId});

  @override
  State<ShelfLayoutViewScreen> createState() => _ShelfLayoutViewScreenState();
}

class _ShelfLayoutViewScreenState extends State<ShelfLayoutViewScreen> {
  ShelfUnit? _unit;
  List<ShelfSlot> _slots = [];
  bool _loading = true;
  int _activeSection = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final unit = await ShelfLayoutService.instance.getUnit(widget.unitId);
    final slots = await ShelfLayoutService.instance.getSlots(widget.unitId);
    if (mounted) {
      setState(() {
        _unit = unit;
        _slots = slots;
        _loading = false;
        if (_activeSection > (unit?.sections ?? 1)) _activeSection = 1;
      });
    }
  }

  List<int> _shelvesIn(int section) {
    final set = <int>{};
    for (final s in _slots) {
      if (s.sectionNo == section) set.add(s.rowNo);
    }
    return set.toList()..sort();
  }

  int _itemsInSection(int section) =>
      _slots.where((s) => s.sectionNo == section).length;

  List<ShelfSlot> _cell(int section, int row) => _slots
      .where((s) => s.sectionNo == section && s.rowNo == row)
      .toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));

  int get _totalItems => _slots.length;
  int get _totalShelves {
    final set = <String>{};
    for (final s in _slots) {
      set.add('${s.sectionNo}:${s.rowNo}');
    }
    return set.length;
  }

  String? get _coverPhoto {
    for (final s in _slots) {
      if (s.photoPath != null && File(s.photoPath!).existsSync()) {
        return s.photoPath;
      }
    }
    return null;
  }

  Future<void> _openScan(int section, int row) async {
    if (_unit == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShelfScanScreen(
        unit: _unit!,
        startSection: section,
        startRow: row,
      ),
    ));
    _load();
  }

  Future<void> _addShelf(int section) async {
    final next = await ShelfLayoutService.instance
        .nextShelfNumber(widget.unitId, section);
    await _openScan(section, next);
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unit;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading || unit == null
          ? const SkeletonList()
          : Column(
              children: [
                _hero(unit),
                if (unit.sections > 1) _sectionTabs(unit),
                Expanded(child: _cabinet(unit, _activeSection)),
              ],
            ),
    );
  }

  // ── HERO ────────────────────────────────────────────────────────────
  Widget _hero(ShelfUnit unit) {
    final topPad = MediaQuery.of(context).padding.top;
    final cover = _coverPhoto;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            Color.lerp(AppTheme.primary, AppTheme.accent, 0.5)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
              ),
              Expanded(
                child: Text(
                  unit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
              if (cover != null)
                GestureDetector(
                  onTap: () => openImageZoom(context,
                      filePath: cover, title: unit.name),
                  child: Container(
                    width: 46,
                    height: 46,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5), width: 1.5),
                    ),
                    child: Image.file(File(cover), fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Row(
              children: [
                _heroStat('${unit.sections}', 'sütun'),
                _heroDivider(),
                _heroStat('$_totalShelves', 'raf'),
                _heroDivider(),
                _heroStat('$_totalItems', 'ürün'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70)),
          ],
        ),
      );

  Widget _heroDivider() => Container(
      width: 1, height: 26, color: Colors.white.withOpacity(0.25));

  // ── SUTUN SEKMELERI ─────────────────────────────────────────────────
  Widget _sectionTabs(ShelfUnit unit) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: unit.sections,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final section = i + 1;
          final sel = _activeSection == section;
          final count = _itemsInSection(section);
          return InkWell(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            onTap: () {
              setState(() => _activeSection = section);
              HapticFeedback.selectionClick();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? AppTheme.primary : AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(AppTheme.rPill),
                border: Border.all(
                    color: sel ? AppTheme.primary : AppTheme.hairline),
                boxShadow: sel ? AppTheme.glow(AppTheme.primary) : null,
              ),
              child: Row(
                children: [
                  Icon(Icons.view_column_rounded,
                      size: 16,
                      color: sel ? Colors.white : AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text('Sütun $section',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color:
                              sel ? Colors.white : AppTheme.textPrimary)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: sel
                          ? Colors.white.withOpacity(0.25)
                          : AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                sel ? Colors.white : AppTheme.primary)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── DOLAP (secili sutun) ────────────────────────────────────────────
  Widget _cabinet(ShelfUnit unit, int section) {
    final shelves = _shelvesIn(section);
    return ListView(
      key: ValueKey('cab_$section'),
      padding: EdgeInsets.fromLTRB(
          14, 16, 14, MediaQuery.of(context).padding.bottom + 24),
      children: [
        // Dolap govdesi: koyu arka panel + yan gövde; icinde raflar.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppTheme.isLight
                  ? [const Color(0xFFE7E9EF), const Color(0xFFD5D8E0)]
                  : [const Color(0xFF1B1E26), const Color(0xFF12141A)],
            ),
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            border: Border.all(
                color: AppTheme.isLight
                    ? const Color(0xFFC2C6D0)
                    : Colors.white.withOpacity(0.06)),
            boxShadow: AppTheme.shadowMd,
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
          child: shelves.isEmpty
              ? _emptyColumn(section)
              : Column(
                  children: [
                    for (int i = 0; i < shelves.length; i++)
                      _shelf3d(section, shelves[i], shelves.length - i),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        // Raf ekle butonu (dolabin altinda).
        OutlinedButton.icon(
          onPressed: () => _addShelf(section),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Bu sütuna raf ekle'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
            minimumSize: const Size.fromHeight(46),
          ),
        ),
      ],
    );
  }

  Widget _emptyColumn(int section) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 12),
      child: Column(
        children: [
          Icon(Icons.shelves,
              size: 40, color: AppTheme.textTertiary.withOpacity(0.5)),
          const SizedBox(height: 10),
          Text('Bu sütun boş',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.isLight
                      ? AppTheme.textSecondary
                      : Colors.white70)),
          const SizedBox(height: 4),
          Text('Aşağıdaki “Raf ekle” ile başla',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  /// Tek raf — GERCEKCI 3D tahta. [displayNo] rafi ustten alta 1..n
  /// gostermek yerine gercek row_no'yu kullaniriz (raf etiketi net kalir).
  Widget _shelf3d(int section, int row, int _) {
    final items = _cell(section, row);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Raf basligi + hizli ekle.
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('Raf $row',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text('${items.length} ürün',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.isLight
                            ? AppTheme.textSecondary
                            : Colors.white60)),
                const Spacer(),
                _miniAddBtn(() => _openScan(section, row)),
              ],
            ),
          ),
          // Urunlerin uzerinde durdugu 3D raf.
          _ShelfDeck(
            child: items.isEmpty
                ? SizedBox(
                    height: 90,
                    child: Center(
                      child: Text('Boş raf',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textTertiary)),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _product3d(items, i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniAddBtn(VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.glow(AppTheme.accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add_a_photo_rounded, size: 14, color: Colors.black),
              SizedBox(width: 4),
              Text('Ekle',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.black)),
            ],
          ),
        ),
      );

  /// Rafta duran tek urun — fotograf + yere basma golgesi + adet rozeti.
  Widget _product3d(List<ShelfSlot> shelfItems, int index) {
    final s = shelfItems[index];
    final hasPhoto = s.photoPath != null && File(s.photoPath!).existsSync();
    return GestureDetector(
      onTap: () => _openProductSheet(shelfItems, index),
      onLongPress: () => _confirmRemove(s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Urun govdesi.
              Container(
                width: 76,
                height: 92,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppTheme.isLight
                      ? Colors.white
                      : const Color(0xFF232733),
                  border: Border.all(
                      color: Colors.black.withOpacity(0.15), width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      offset: const Offset(0, 6),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: hasPhoto
                    ? Image.file(File(s.photoPath!), fit: BoxFit.cover)
                    : Center(
                        child: Icon(Icons.inventory_2_rounded,
                            size: 26, color: AppTheme.textTertiary),
                      ),
              ),
              // Adet rozeti (ayni hucrede birden fazla ayni urun degil;
              // her slot 1 adet — yine de sira/adet gostergesi olarak seq).
              // Not: adet kavrami slot bazli degil; rozet index yerine
              // toplam ayni barkod sayisini gosterir.
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(ShelfSlot s) async {
    final name = (s.productName?.trim().isNotEmpty ?? false)
        ? s.productName!.trim()
        : s.barcode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raftan Kaldır'),
        content: Text('"$name" bu raftan kaldırılsın mı?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok == true && s.id != null) {
      await ShelfLayoutService.instance.deleteSlot(s.id!);
      HapticFeedback.mediumImpact();
      await _load();
      if (!mounted) return;
      // GERİ AL: kaldırılan ürünü aynı raf konumuna geri ekle (foto korunur).
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name kaldırıldı'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Geri Al',
            textColor: AppTheme.accent,
            onPressed: () async {
              await ShelfLayoutService.instance.addSlot(
                unitId: s.unitId,
                sectionNo: s.sectionNo,
                rowNo: s.rowNo,
                barcode: s.barcode,
                productName: s.productName,
                photoPath: s.photoPath,
              );
              _load();
            },
          ),
        ),
      );
    }
  }

  /// ── ALTTAN KAYAN URUN PENCERESI ──
  Future<void> _openProductSheet(
      List<ShelfSlot> shelfItems, int initialIndex) async {
    final removed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ProductSheet(
        unitName: _unit?.name ?? 'Reyon',
        items: shelfItems,
        initialIndex: initialIndex,
      ),
    );
    if (removed == true) _load();
  }
}

/// GERCEKCI 3D RAF TAHTASI: cocuk (urunler) tahtanin USTUNDE durur; altta
/// one dogru egimli kalin bir tahta on-yuzu + govde golgesi cizilir. Boylece
/// urunler magaza rafinda duruyormus gibi derinlik kazanir.
class _ShelfDeck extends StatelessWidget {
  final Widget child;
  const _ShelfDeck({required this.child});

  @override
  Widget build(BuildContext context) {
    final wood = AppTheme.isLight
        ? const Color(0xFFBFA07A) // acik ahsap
        : const Color(0xFF3A3F4C); // koyu metal-ahsap
    final woodDark = AppTheme.isLight
        ? const Color(0xFF9C8161)
        : const Color(0xFF2A2E39);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Urunler.
        child,
        // Raf tahtasi ust yuzeyi (ince, parlak kenar).
        Container(
          height: 4,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [wood, woodDark],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        // Tahtanin ONE egimli on-yuzu (trapez) + govde golgesi.
        SizedBox(
          height: 16,
          child: CustomPaint(
            painter: _DeckFacePainter(top: wood, bottom: woodDark),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

/// Rafin one dogru egimli on yuzu: ustte tam genislik, altta hafif iceri —
/// tek kacis noktali perspektif hissi. Alt kenarda yumusak golge.
class _DeckFacePainter extends CustomPainter {
  final Color top;
  final Color bottom;
  _DeckFacePainter({required this.top, required this.bottom});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const inset = 10.0; // alt kenarin her iki yandan iceri kacma miktari
    final face = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w - inset, h)
      ..lineTo(inset, h)
      ..close();
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // Alt golge (rafin dip cizgisi).
    canvas.drawLine(
      Offset(inset, h - 0.5),
      Offset(w - inset, h - 0.5),
      Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DeckFacePainter old) =>
      old.top != top || old.bottom != bottom;
}

/// Alttan kayan urun bilgi penceresi (PageView'lu).
class _ProductSheet extends StatefulWidget {
  final String unitName;
  final List<ShelfSlot> items;
  final int initialIndex;
  const _ProductSheet({
    required this.unitName,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _removedAny = false;

  // Barkod dizini bilgileri (stok kodu, dizindeki ad) — sayfa basina onbellek.
  final Map<String, BarcodeEntry?> _dirCache = {};

  Future<BarcodeEntry?> _dirEntry(String barcode) async {
    if (_dirCache.containsKey(barcode)) return _dirCache[barcode];
    BarcodeEntry? e;
    try {
      e = await BarcodeDirectoryDataSource(DatabaseService.instance)
          .findEntryByBarcode(barcode);
    } catch (_) {}
    _dirCache[barcode] = e;
    return e;
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.82;
    return SizedBox(
      height: h,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: AppTheme.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Sayfa gostergesi: 3/11 + kaydirma ipucu.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text('${_index + 1} / ${widget.items.length}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textTertiary)),
                const Spacer(),
                if (widget.items.length > 1)
                  Row(
                    children: [
                      Icon(Icons.swipe_rounded,
                          size: 14, color: AppTheme.textTertiary),
                      const SizedBox(width: 4),
                      Text('Kaydırarak diğer ürünler',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textTertiary)),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _productPage(widget.items[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productPage(ShelfSlot s) {
    final hasPhoto = s.photoPath != null && File(s.photoPath!).existsSync();
    final name = (s.productName?.trim().isNotEmpty ?? false)
        ? s.productName!.trim()
        : s.barcode;
    final is13 = RegExp(r'^\d{13}$').hasMatch(s.barcode);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        // ── FOTO (dokununca tam ekran zoom) ──
        GestureDetector(
          onTap: hasPhoto
              ? () => openImageZoom(context,
                  filePath: s.photoPath, title: name)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 240,
              width: double.infinity,
              color: AppTheme.surfaceAlt,
              child: hasPhoto
                  ? Image.file(File(s.photoPath!), fit: BoxFit.cover)
                  : Icon(Icons.inventory_2_rounded,
                      size: 56, color: AppTheme.textTertiary),
            ),
          ),
        ).animate().fadeIn(duration: 200.ms),
        const SizedBox(height: 14),

        Text(name,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
          '${widget.unitName} · Sütun ${s.sectionNo} · Raf ${s.rowNo} · '
          '${s.seq + 1}. sıra',
          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),

        // ── BARKOD (resim olarak cizilir) ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white, // barkod SIYAH cizgilidir; zemin hep beyaz
            borderRadius: BorderRadius.circular(14),
          ),
          child: BarcodeWidget(
            barcode: is13 ? Barcode.ean13() : Barcode.code128(),
            data: s.barcode,
            drawText: true,
            height: 80,
            color: Colors.black,
            errorBuilder: (_, __) => Text(s.barcode,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black)),
          ),
        ),
        const SizedBox(height: 14),

        // ── DIZIN BILGILERI (stok kodu vs.) ──
        FutureBuilder<BarcodeEntry?>(
          future: _dirEntry(s.barcode),
          builder: (_, snap) {
            final e = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.qr_code_rounded, 'Barkod', s.barcode),
                if (e?.stockCode?.trim().isNotEmpty ?? false)
                  _infoRow(Icons.tag_rounded, 'Stok kodu', e!.stockCode!),
                if (e != null && e.productName != name)
                  _infoRow(Icons.badge_rounded, 'Dizindeki ad',
                      e.productName),
                _infoRow(
                    Icons.event_rounded,
                    'Eklenme',
                    '${s.createdAt.day.toString().padLeft(2, '0')}.'
                        '${s.createdAt.month.toString().padLeft(2, '0')}.'
                        '${s.createdAt.year}'),
              ],
            );
          },
        ),
        const SizedBox(height: 18),

        // ── AKSIYONLAR ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Ürünü raftan kaldır'),
                      content: Text(name),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Vazgeç')),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.statusExpired),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Kaldır')),
                      ],
                    ),
                  );
                  if (ok == true && s.id != null) {
                    await ShelfLayoutService.instance.deleteSlot(s.id!);
                    _removedAny = true;
                    if (mounted) Navigator.of(context).pop(true);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text('Raftan kaldır'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.statusExpired,
                  side: BorderSide(
                      color: AppTheme.statusExpired.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_removedAny),
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Kapat'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textTertiary),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textTertiary)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
