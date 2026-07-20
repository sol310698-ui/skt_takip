import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'pallet_detail_screen.dart';
import 'warehouse_detail_screen.dart';

/// Depo listesi — kartlar + "Yeni Depo" sihirbazi.
class WarehouseListScreen extends StatefulWidget {
  /// Nav sekmesi koku olarak mi acildi (geri tusu gosterilmez).
  final bool isTabRoot;
  const WarehouseListScreen({super.key, this.isTabRoot = false});

  @override
  State<WarehouseListScreen> createState() => _WarehouseListScreenState();
}

class _WarehouseListScreenState extends State<WarehouseListScreen> {
  List<Warehouse> _warehouses = [];
  // Her depo için ozet: warehouseId -> (palet sayisi, cesit, toplam adet)
  final Map<int, ({int pallets, int types, int qty})> _stats = {};
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
    _stats.clear();
    for (final w in list) {
      final floor =
          await WarehouseService.instance.getFloorPallets(w.id!);
      if (floor.isNotEmpty) _floorByWarehouse[w.id!] = floor;
      // Depo ozeti: tum paletler uzerinden cesit + adet topla.
      final all = await WarehouseService.instance.getAllPallets(w.id!);
      _stats[w.id!] = (
        pallets: all.length,
        types: all.fold(0, (s, p) => s + p.itemTypes),
        qty: all.fold(0, (s, p) => s + p.totalQty),
      );
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

  // ── YENIDEN TASARIM: hero baslik + ozet serit + kart listesi ──────
  ({int pallets, int types, int qty}) get _totals => (
        pallets: _stats.values.fold(0, (s, e) => s + e.pallets),
        types: _stats.values.fold(0, (s, e) => s + e.types),
        qty: _stats.values.fold(0, (s, e) => s + e.qty),
      );

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
                : _warehouses.isEmpty
                    ? ListView(
                        padding:
                            EdgeInsets.fromLTRB(16, 20, 16, bottomPad),
                        children: [
                          const SizedBox(height: 24),
                          Icon(Icons.warehouse_rounded,
                              size: 56,
                              color: AppTheme.accent.withOpacity(0.6)),
                          const SizedBox(height: 12),
                          const Text('Henüz depo yok',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            'Sütunları, rafları ve palet kapasitelerini '
                            'girerek ilk deponuzu oluşturun.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppTheme.textTertiary),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: FilledButton.icon(
                              onPressed: _newWarehouse,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Yeni Depo'),
                            ),
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                              16, 14, 16, bottomPad),
                          children: [
                            ..._warehouses.map(_card),
                            if (_hasFloor) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const Icon(
                                      Icons
                                          .vertical_align_bottom_rounded,
                                      size: 18,
                                      color: AppTheme.amber),
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
          ),
        ],
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

  /// Gradyanli hero baslik: durum çubuğunun arkasina uzanir, altinda
  /// deponun genel ozeti (depo/palet/çeşit/adet) yer alir.
  Widget _hero() {
    final t = _totals;
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent,
            Color.lerp(AppTheme.accent, AppTheme.primary, 0.55)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.warehouse_rounded,
                    color: Colors.black, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Depo',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.black)),
                    Text('Sütun, raf ve palet yönetimi',
                        style: TextStyle(
                            fontSize: 12, color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
          if (!_loading && _warehouses.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
              child: Row(
                children: [
                  _heroStat('${_warehouses.length}', 'depo'),
                  _heroDivider(),
                  _heroStat('${t.pallets}', 'palet'),
                  _heroDivider(),
                  _heroStat('${t.types}', 'çeşit'),
                  _heroDivider(),
                  _heroStat('${t.qty}', 'adet'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.black)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5, color: Colors.black87)),
          ],
        ),
      );

  Widget _heroDivider() => Container(
        width: 1, height: 26, color: Colors.black.withOpacity(0.15));

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
                      style: TextStyle(
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
    final st = _stats[w.id];
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => _open(w),
      onLongPress: () => _delete(w),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accent.withOpacity(0.16),
              AppTheme.accent.withOpacity(0.04),
            ],
          ),
          border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            // Ust: ikon + isim + tarih + ok
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.22),
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
                                fontSize: 16.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                            'Oluşturuldu: ${DateFormat('dd.MM.yyyy').format(w.createdAt)}',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textTertiary)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textTertiary),
                ],
              ),
            ),
            // Alt: ozet istatistikler seridi
            if (st != null)
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(AppTheme.rLg)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    _statChip(Icons.inventory_2_rounded, '${st.pallets}',
                        'palet'),
                    _statDivider(),
                    _statChip(Icons.category_rounded, '${st.types}', 'çeşit'),
                    _statDivider(),
                    _statChip(
                        Icons.numbers_rounded, '${st.qty}', 'adet'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: AppTheme.accent),
              const SizedBox(width: 5),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 28,
        color: AppTheme.accent.withOpacity(0.18),
      );
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
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.accent),
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
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textTertiary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
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
                          style: TextStyle(
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _duplicateColumn(i),
            icon: const Icon(Icons.copy_all_rounded, size: 16),
            label: const Text('Bu Ayarla Çoğalt',
                style: TextStyle(fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
              minimumSize: const Size(0, 34),
            ),
          ),
        ],
      ),
    );
  }

  /// "Bu sütunu N kez oluştur" — ayni raf sayisi/kapasiteyle N adet YENI
  /// sutun ekler; her sutunu teker teker ayarlamak zorunda kalinmaz
  /// (orn. 12 ayni sutunlu depo kurulumu icin).
  Future<void> _duplicateColumn(int i) async {
    final src = _columns[i];
    final ctrl = TextEditingController(text: '1');
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aynı Ayarlarla Sütun Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${src.shelfCount} raf, raf başına ${src.capacityPerShelf} palet '
                'ayarlarıyla kaç YENİ sütun eklensin?',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                labelText: 'Eklenecek sütun sayısı',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (count == null || count < 1) return;
    setState(() {
      final copies = List.generate(
        count.clamp(1, 200),
        (_) => _ColumnDef(
            shelfCount: src.shelfCount,
            capacityPerShelf: src.capacityPerShelf),
      );
      _columns.insertAll(i + 1, copies);
    });
  }

  Widget _stepper(String label, int value, ValueChanged<int> onChange) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
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
