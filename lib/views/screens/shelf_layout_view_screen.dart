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
///  Bir reyonu satir satir gosterir. Her satir, bolumlere ayrilmistir ve her
///  hucredeki urun fotograflari SOLDAN SAGA kucuk kucuk dizilir — boylece
///  raftaki gercek dizilim gorunur. Bos bir hucreye dokununca o hucre icin
///  okutma ekrani acilir; bir fotografa dokununca buyutulur.
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
        actions: [
          if (unit != null)
            IconButton(
              tooltip: 'Okutmaya başla',
              onPressed: () => _openScan(1, 1),
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
        ],
      ),
      body: _loading || unit == null
          ? const LoadingState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
              itemCount: unit.rows,
              itemBuilder: (_, ri) => _rowBlock(unit, ri + 1),
            ),
    );
  }

  Widget _rowBlock(ShelfUnit unit, int row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.card(),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Satır $row',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accent,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Bolumler yan yana; her bolumun urunleri soldan saga.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(unit.sections, (si) {
              final section = si + 1;
              return Expanded(child: _sectionCell(section, row));
            }),
          ),
        ],
      ),
    );
  }

  Widget _sectionCell(int section, int row) {
    final items = _cell(section, row);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openScan(section, row),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('B$section',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textTertiary)),
            const SizedBox(height: 4),
            if (items.isEmpty)
              Container(
                height: 46,
                alignment: Alignment.center,
                child: Icon(Icons.add_rounded,
                    size: 18, color: AppTheme.textTertiary),
              )
            else
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: items.map(_miniThumb).toList(),
              ),
          ],
        ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 42,
          height: 46,
          color: AppTheme.surfaceAlt,
          child: hasPhoto
              ? Image.file(File(s.photoPath!), fit: BoxFit.cover)
              : Icon(Icons.inventory_2_rounded,
                  size: 18, color: AppTheme.textTertiary),
        ),
      ),
    );
  }
}
