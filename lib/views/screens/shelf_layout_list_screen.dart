import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'shelf_layout_view_screen.dart';
import 'shelf_scan_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYON DIZILIM — KUS BAKISI LISTE
/// ────────────────────────────────────────────────────────────────────
///  Olusturulan reyonlar kart izgarasi olarak gorunur. Bir reyona basinca
///  dizilim (planogram) ekrani acilir. "+ Reyon" ile yeni reyon olusturulur
///  (ad, bolum sayisi, satir sayisi). Bir depoya bagli acilirsa (warehouseId)
///  yalnizca o deponun reyonlari listelenir.
/// ════════════════════════════════════════════════════════════════════
class ShelfLayoutListScreen extends StatefulWidget {
  final int? warehouseId;
  final String? warehouseName;
  const ShelfLayoutListScreen({super.key, this.warehouseId, this.warehouseName});

  @override
  State<ShelfLayoutListScreen> createState() => _ShelfLayoutListScreenState();
}

class _ShelfLayoutListScreenState extends State<ShelfLayoutListScreen> {
  List<ShelfUnitSummary> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final units = await ShelfLayoutService.instance
        .getUnitSummaries(warehouseId: widget.warehouseId);
    if (mounted) setState(() {
      _units = units;
      _loading = false;
    });
  }

  Future<void> _newUnit() async {
    final nameCtrl = TextEditingController(
        text: 'Reyon ${_units.length + 1}');
    int sections = 4;
    int rows = 5;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Yeni Reyon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reyon adı',
                  hintText: 'Reyon 1, Bakliyat...',
                ),
              ),
              const SizedBox(height: 18),
              _stepper(
                label: 'Bölüm (sütun)',
                help: 'Reyonun soldan sağa kaç bölmesi var',
                value: sections,
                onChanged: (v) => setD(() => sections = v),
              ),
              const SizedBox(height: 12),
              _stepper(
                label: 'Satır (kat)',
                help: 'Üstten alta kaç raf/kat var',
                value: rows,
                onChanged: (v) => setD(() => rows = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Oluştur')),
          ],
        ),
      ),
    );

    if (created != true) return;
    final id = await ShelfLayoutService.instance.createUnit(
      name: nameCtrl.text.trim().isEmpty ? 'Reyon' : nameCtrl.text.trim(),
      sections: sections,
      rows: rows,
      warehouseId: widget.warehouseId,
    );
    await _load();
    if (!mounted) return;
    // Yeni reyon olusturunca dogrudan okutmaya baslamak icin tarama ekranini ac.
    final unit = await ShelfLayoutService.instance.getUnit(id);
    if (unit != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ShelfScanScreen(unit: unit)));
      _load();
    }
  }

  Widget _stepper({
    required String label,
    required String help,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(help,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 34,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        IconButton.filledTonal(
          onPressed: value < 20 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(ShelfUnitSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reyonu Sil'),
        content: Text(
            '"${s.unit.name}" ve içindeki ${s.itemCount} ürün fotoğrafı '
            'silinecek. Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await ShelfLayoutService.instance.deleteUnit(s.unit.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.warehouseName != null
        ? 'Reyonlar — ${widget.warehouseName}'
        : 'Reyon Dizilim';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.accent),
      ),
      body: _loading
          ? const LoadingState()
          : _units.isEmpty
              ? EmptyState(
                  icon: Icons.grid_view_rounded,
                  iconColor: AppTheme.accent,
                  title: 'Henüz reyon yok',
                  subtitle:
                      'Bir reyon oluşturun (bölüm ve satır sayısı), sonra '
                      'ürünleri okutup fotoğraflayın. Dizilimi kuş bakışı '
                      'görebilirsiniz.',
                  action: FilledButton.icon(
                    onPressed: _newUnit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Yeni Reyon'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _units.length,
                    itemBuilder: (_, i) => _card(_units[i]),
                  ),
                ),
      floatingActionButton: _units.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _newUnit,
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yeni Reyon'),
            ),
    );
  }

  Widget _card(ShelfUnitSummary s) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ShelfLayoutViewScreen(unitId: s.unit.id!)));
        _load();
      },
      onLongPress: () => _confirmDelete(s),
      child: Container(
        decoration: AppTheme.card(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kapak: ilk urunun fotografi (yoksa izgara ikonu).
            Expanded(
              child: Container(
                color: AppTheme.surfaceAlt,
                child: s.coverPhoto != null && File(s.coverPhoto!).existsSync()
                    ? Image.file(File(s.coverPhoto!), fit: BoxFit.cover)
                    : Center(
                        child: Icon(Icons.grid_view_rounded,
                            size: 46,
                            color: AppTheme.accent.withOpacity(0.4)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.unit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '${s.unit.sections} bölüm × ${s.unit.rows} satır'
                    '  •  ${s.itemCount} ürün',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
