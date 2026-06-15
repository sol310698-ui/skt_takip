import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'pallet_detail_screen.dart';
import 'warehouse_detail_screen.dart';

/// Depo listesi — kartlar + "Yeni Depo" sihirbazi.
class WarehouseListScreen extends StatefulWidget {
  const WarehouseListScreen({super.key});

  @override
  State<WarehouseListScreen> createState() => _WarehouseListScreenState();
}

class _WarehouseListScreenState extends State<WarehouseListScreen> {
  List<Warehouse> _warehouses = [];
  // Her depo için zemin paletleri: warehouseId -> paletler
  final Map<int, List<PalletSummary>> _floorByWarehouse = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await WarehouseService.instance.getWarehouses();
    _floorByWarehouse.clear();
    for (final w in list) {
      final floor =
          await WarehouseService.instance.getFloorPallets(w.id!);
      if (floor.isNotEmpty) _floorByWarehouse[w.id!] = floor;
    }
    if (!mounted) return;
    setState(() {
      _warehouses = list;
      _loading = false;
    });
  }

  bool get _hasFloor => _floorByWarehouse.isNotEmpty;

  Future<void> _open(Warehouse w) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WarehouseDetailScreen(warehouseId: w.id!)));
    _load();
  }

  Future<void> _delete(Warehouse w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Depoyu Sil'),
        content: Text(
            '"${w.name}" deposu, tüm rafları, paletleri ve ürünleriyle '
            'birlikte silinecek. Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await WarehouseService.instance.deleteWarehouse(w.id!);
      _load();
    }
  }

  Future<void> _newWarehouse() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WarehouseWizardScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Depolar'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const LoadingState()
          : _warehouses.isEmpty
              ? EmptyState(
                  icon: Icons.warehouse_rounded,
                  iconColor: AppTheme.accent,
                  title: 'Henüz depo yok',
                  subtitle:
                      'Sütunları, rafları ve palet kapasitelerini girerek '
                      'ilk deponuzu oluşturun.',
                  action: FilledButton.icon(
                    onPressed: _newWarehouse,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Yeni Depo'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      const SectionLabel('Depolar'),
                      const SizedBox(height: 8),
                      ..._warehouses.map(_card),
                      if (_hasFloor) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.vertical_align_bottom_rounded,
                                size: 18, color: AppTheme.amber),
                            const SizedBox(width: 6),
                            Text(
                                'Zemindekiler (${_floorByWarehouse.values.fold(0, (s, l) => s + l.length)})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppTheme.amber)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._buildFloorSection(),
                      ],
                    ],
                  ),
                ),
      floatingActionButton: _warehouses.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _newWarehouse,
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yeni Depo'),
            ),
    );
  }

  // Zemin paletlerini depo bazında listele.
  List<Widget> _buildFloorSection() {
    final widgets = <Widget>[];
    for (final entry in _floorByWarehouse.entries) {
      final wh = _warehouses
          .where((w) => w.id == entry.key)
          .map((w) => w.name)
          .firstOrNull;
      for (final p in entry.value) {
        widgets.add(_floorPalletTile(p, wh ?? 'Depo', entry.key));
      }
    }
    return widgets;
  }

  Widget _floorPalletTile(PalletSummary p, String whName, int warehouseId) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PalletDetailScreen(
              palletId: p.pallet.id!, warehouseId: warehouseId),
        ));
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(accentColor: AppTheme.amber),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppTheme.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.vertical_align_bottom_rounded,
                  color: AppTheme.amber, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.pallet.code,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('$whName • ${p.itemTypes} çeşit • ${p.totalQty} adet',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: const Text('Zemin',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.amber)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Warehouse w) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => _open(w),
      onLongPress: () => _delete(w),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.card(accentColor: AppTheme.accent),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.warehouse_rounded,
                  color: AppTheme.accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      'Oluşturuldu: ${DateFormat('dd.MM.yyyy').format(w.createdAt)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  Depo oluşturma sihirbazı
/// ════════════════════════════════════════════════════════════════════
class WarehouseWizardScreen extends StatefulWidget {
  const WarehouseWizardScreen({super.key});

  @override
  State<WarehouseWizardScreen> createState() => _WarehouseWizardScreenState();
}

/// Bir sutunun raf tanimi (kurulum sirasinda).
class _ColumnDef {
  int shelfCount;
  int capacityPerShelf;
  _ColumnDef({this.shelfCount = 3, this.capacityPerShelf = 2});
}

class _WarehouseWizardScreenState extends State<WarehouseWizardScreen> {
  final _nameCtrl = TextEditingController();
  final List<_ColumnDef> _columns = [_ColumnDef()];
  bool _saving = false;

  int get _totalShelves =>
      _columns.fold(0, (s, c) => s + c.shelfCount);
  int get _totalCapacity =>
      _columns.fold(0, (s, c) => s + c.shelfCount * c.capacityPerShelf);

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Depo adı girin')),
      );
      return;
    }
    setState(() => _saving = true);

    final id = await WarehouseService.instance.createWarehouse(name);
    final shelves = <WhShelf>[];
    for (int c = 0; c < _columns.length; c++) {
      final col = _columns[c];
      for (int s = 1; s <= col.shelfCount; s++) {
        shelves.add(WhShelf(
          warehouseId: id,
          columnNo: c + 1,
          shelfNo: s,
          capacity: col.capacityPerShelf,
        ));
      }
    }
    await WarehouseService.instance.addShelves(id, shelves);

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Yeni Depo'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Depo adı',
              hintText: 'Örn: Ana Depo, Soğuk Hava...',
              prefixIcon: Icon(Icons.warehouse_rounded),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Sütunlar',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text('${_columns.length} sütun • $_totalShelves raf',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textTertiary)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Her sütun için raf sayısını ve raf başına kaç palet alacağını girin.',
            style:
                TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          ...List.generate(_columns.length, (i) => _columnCard(i)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _columns.add(_ColumnDef())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Sütun Ekle'),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            color: AppTheme.surface, boxShadow: AppTheme.shadowMd),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Toplam $_totalCapacity palet kapasitesi',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      Text('$_totalShelves raf',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Depoyu Oluştur'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.black),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _columnCard(int i) {
    final col = _columns[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${i + 1}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accent)),
              ),
              const SizedBox(width: 10),
              Text('Sütun ${i + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (_columns.length > 1)
                InkWell(
                  onTap: () => setState(() => _columns.removeAt(i)),
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppTheme.statusExpired),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _stepper('Raf sayısı', col.shelfCount, (v) {
            setState(() => col.shelfCount = v.clamp(1, 50));
          }),
          const SizedBox(height: 8),
          _stepper('Raf başına palet', col.capacityPerShelf, (v) {
            setState(() => col.capacityPerShelf = v.clamp(1, 20));
          }),
        ],
      ),
    );
  }

  Widget _stepper(String label, int value, ValueChanged<int> onChange) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13.5, color: AppTheme.textSecondary)),
        ),
        _roundBtn(Icons.remove_rounded, () => onChange(value - 1)),
        Container(
          width: 44,
          alignment: Alignment.center,
          child: Text('$value',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        _roundBtn(Icons.add_rounded, () => onChange(value + 1)),
      ],
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: AppTheme.textPrimary),
      ),
    );
  }
}
