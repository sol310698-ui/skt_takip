import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
import 'shelf_scan_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYON DIZILIM — KUS BAKISI GORUNUM (PLANOGRAM)
/// ────────────────────────────────────────────────────────────────────
///  Yapi (kullanicinin modeli):
///     Reyon  →  SUTUN (section)  →  RAF (row)  →  URUNLER (sinirsiz)
///
///  Reyon olusturulurken SADECE sutun sayisi belirlenir. Raf sayisi
///  SABIT DEGILDIR: her sutuna istenildigi kadar raf eklenir ("+ Raf"),
///  her rafa da istenildigi kadar urun okutulur (sinir yok). Yani bir rafa
///  5 urun, digerine 10 urun eklenebilir.
///
///  Bu ekran her sutunu ayri bir kart olarak, altinda kendi raflarini
///  (ve her raftaki urun fotograflarini soldan saga) gosterir. Rafa
///  dokununca o rafa urun eklemek icin okutma ekrani acilir; bir fotografa
///  dokununca buyutulur.
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

  /// Bir sutundaki raf numaralari (icinde urun olanlar), artan.
  List<int> _shelvesIn(int section) {
    final set = <int>{};
    for (final s in _slots) {
      if (s.sectionNo == section) set.add(s.rowNo);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Bir raftaki urunler, soldan saga (seq).
  List<ShelfSlot> _cell(int section, int row) => _slots
      .where((s) => s.sectionNo == section && s.rowNo == row)
      .toList()
    ..sort((a, b) => a.seq.compareTo(b.seq));

  /// Belirli bir (sutun, raf) hucresine urun eklemek icin okutma ekrani.
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

  /// Sutuna YENI raf ekle: siradaki raf numarasini bulup okutmayi acar.
  Future<void> _addShelf(int section) async {
    final next =
        await ShelfLayoutService.instance.nextShelfNumber(widget.unitId, section);
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.card(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sutun basligi.
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
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textTertiary)),
            ],
          ),
          const SizedBox(height: 10),

          // Bu sutunun raflari (yoksa bilgi).
          if (shelves.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Henüz raf yok — aşağıdan raf ekleyin',
                  style: TextStyle(color: AppTheme.textTertiary)),
            )
          else
            ...shelves.map((r) => _shelfRow(section, r)),

          const SizedBox(height: 6),
          // Yeni raf ekle.
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

  Widget _shelfRow(int section, int row) {
    final items = _cell(section, row);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Raf $row',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('(${items.length} ürün)',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
              const Spacer(),
              // Bu rafa daha urun ekle.
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
          const SizedBox(height: 8),
          // Urun fotograflari soldan saga (raftaki gercek dizilim).
          items.isEmpty
              ? SizedBox(
                  height: 46,
                  child: Center(
                    child: Text('Bu raf boş',
                        style: TextStyle(
                            color: AppTheme.textTertiary, fontSize: 12)),
                  ),
                )
              : Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: items.map(_miniThumb).toList(),
                ),
        ],
      ),
    );
  }

  Widget _miniThumb(ShelfSlot s) {
    final hasPhoto = s.photoPath != null && File(s.photoPath!).existsSync();
    return GestureDetector(
      onTap: hasPhoto
          ? () => openImageZoom(context,
              filePath: s.photoPath, title: s.productName)
          : null,
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ürünü kaldır'),
            content: Text(s.productName ?? s.barcode),
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
        if (ok == true) {
          await ShelfLayoutService.instance.deleteSlot(s.id!);
          _load();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 48,
          height: 52,
          color: AppTheme.surfaceAlt,
          child: hasPhoto
              ? Image.file(File(s.photoPath!), fit: BoxFit.cover)
              : Icon(Icons.inventory_2_rounded,
                  size: 20, color: AppTheme.textTertiary),
        ),
      ),
    );
  }
}
