import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
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
///  REYON DIZILIM — GERCEK RAF GORUNUMU
/// ────────────────────────────────────────────────────────────────────
///  v2 tasarim:
///   - Her raf, ALTINDA kalin bir "raf tahtasi" olan yatay bir seruttir;
///     urunler tahtanin USTUNDE duruyormus gibi alt-hizali dizilir ve
///     gercek raftaki gibi SOLDAN SAGA kaydirilir.
///   - Urune dokununca ALTTAN KAYAN bilgi penceresi acilir: buyuk foto,
///     urun adi, CIZILMIS BARKOD (EAN-13/Code128), stok kodu, konum,
///     kaldirma. Fotoyu SAGA/SOLA kaydirinca ayni raftaki DIGER urunlere
///     gecilir (PageView) — raf uzerinde parmakla gezinme hissi.
///   - Fotoya dokununca tam ekran zoom.
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

  List<ShelfSlot> _cell(int section, int row) => _slots
      .where((s) => s.sectionNo == section && s.rowNo == row)
      .toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));

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
      appBar: AppBar(
        title: Text(unit?.name ?? 'Reyon'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.accent),
      ),
      body: _loading || unit == null
          ? const LoadingState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
              itemCount: unit.sections,
              itemBuilder: (_, si) => _columnBlock(unit, si + 1),
            ),
    );
  }

  Widget _columnBlock(ShelfUnit unit, int section) {
    final shelves = _shelvesIn(section);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppTheme.card(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Sütun $section',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        fontSize: 13)),
              ),
              const Spacer(),
              Text('${shelves.length} raf',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
            ],
          ),
          const SizedBox(height: 10),
          if (shelves.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Henüz raf yok — aşağıdan raf ekleyin',
                  style: TextStyle(color: AppTheme.textTertiary)),
            )
          else
            ...shelves.map((r) => _shelfBoard(section, r)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addShelf(section),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Raf ekle'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }

  /// ── GERCEK RAF: urunler + altinda kalin raf tahtasi ──
  Widget _shelfBoard(int section, int row) {
    final items = _cell(section, row);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Raf $row',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('(${items.length} ürün)',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
              const Spacer(),
              InkWell(
                onTap: () => _openScan(section, row),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add_a_photo_rounded,
                          size: 14, color: AppTheme.accent),
                      SizedBox(width: 4),
                      Text('Ürün ekle',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Urunler: raf tahtasinin USTUNDE, yatay kaydirmali.
          SizedBox(
            height: 84,
            child: items.isEmpty
                ? Center(
                    child: Text('Bu raf boş',
                        style: TextStyle(
                            color: AppTheme.textTertiary, fontSize: 12)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => Align(
                      alignment: Alignment.bottomCenter,
                      child: _productOnShelf(items, i),
                    ),
                  ),
          ),
          // RAF TAHTASI: kalin, golgeli cubuk — urunler bunun ustunde durur.
          Container(
            height: 10,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accent.withOpacity(0.85),
                  AppTheme.accent.withOpacity(0.45),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  offset: const Offset(0, 3),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productOnShelf(List<ShelfSlot> shelfItems, int index) {
    final s = shelfItems[index];
    final hasPhoto = s.photoPath != null && File(s.photoPath!).existsSync();
    return GestureDetector(
      onTap: () => _openProductSheet(shelfItems, index),
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(6)),
        child: Container(
          width: 58,
          height: 76,
          color: AppTheme.surfaceAlt,
          child: hasPhoto
              ? Image.file(File(s.photoPath!), fit: BoxFit.cover)
              : Icon(Icons.inventory_2_rounded,
                  size: 22, color: AppTheme.textTertiary),
        ),
      ),
    );
  }

  /// ── ALTTAN KAYAN URUN PENCERESI ──
  /// Sayfalar arasi SAGA/SOLA kaydirma = ayni raftaki diger urunler.
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
