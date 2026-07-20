import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'shelf_layout_view_screen.dart';

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
  /// Nav sekmesi koku olarak mi acildi (hero baslikta geri tusu yok).
  final bool isTabRoot;
  const ShelfLayoutListScreen(
      {super.key, this.warehouseId, this.warehouseName, this.isTabRoot = false});

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
                label: 'Sütun sayısı',
                help: 'Reyonun soldan sağa kaç sütunu var. Raflar ve '
                    'ürünler sonra serbestçe eklenir (sınır yok).',
                value: sections,
                onChanged: (v) => setD(() => sections = v),
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
      warehouseId: widget.warehouseId,
    );
    await _load();
    if (!mounted) return;
    // Yeni reyon olusturunca dogrudan dizilim (planogram) ekranini ac;
    // kullanici oradan sutun sutun raf/urun ekler.
    final unit = await ShelfLayoutService.instance.getUnit(id);
    if (unit != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ShelfLayoutViewScreen(unitId: unit.id!)));
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
    final bottomPad = MediaQuery.of(context).padding.bottom + 16;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _hero(),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _units.isEmpty
                    ? EmptyState(
                        icon: Icons.grid_view_rounded,
                        iconColor: AppTheme.primary,
                        title: 'Henüz reyon yok',
                        subtitle:
                            'Bir reyon oluşturun (bölüm ve satır sayısı), '
                            'sonra ürünleri okutup fotoğraflayın. Dizilimi '
                            'kuş bakışı görebilirsiniz.',
                        action: FilledButton.icon(
                          onPressed: _newUnit,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Yeni Reyon'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: GridView.builder(
                          padding:
                              EdgeInsets.fromLTRB(12, 14, 12, bottomPad),
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
          ),
        ],
      ),
      floatingActionButton: _units.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _newUnit,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yeni Reyon'),
            ),
    );
  }

  /// Gradyanli hero baslik — Reyon sekmesinin kimligi (primary tonlari).
  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    final canPop = !widget.isTabRoot && Navigator.of(context).canPop();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(canPop ? 8 : 20, topPad + 14, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            Color.lerp(AppTheme.primary, AppTheme.accent, 0.45)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.shelves, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.warehouseName != null
                      ? 'Reyonlar — ${widget.warehouseName}'
                      : 'Reyon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
                Text(
                  _loading
                      ? 'Dizilimler yükleniyor…'
                      : '${_units.length} reyon · kuş bakışı dizilim',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
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
                    '${s.unit.sections} sütun  •  ${s.itemCount} ürün',
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
