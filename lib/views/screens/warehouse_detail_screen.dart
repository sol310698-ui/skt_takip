import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';
import 'pallet_detail_screen.dart';

/// Depo detayi: Harita (sutun×raf izgara) + Liste sekmeleri + arama.
class WarehouseDetailScreen extends StatefulWidget {
  final int warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  @override
  State<WarehouseDetailScreen> createState() =>
      _WarehouseDetailScreenState();
}

class _WarehouseDetailScreenState extends State<WarehouseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  Warehouse? _warehouse;
  List<ShelfSummary> _shelves = [];
  List<PalletSummary> _allPallets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final w = await WarehouseService.instance.getWarehouse(widget.warehouseId);
    final shelves =
        await WarehouseService.instance.getShelfSummaries(widget.warehouseId);
    final all =
        await WarehouseService.instance.getAllPallets(widget.warehouseId);

    if (!mounted) return;
    setState(() {
      _warehouse = w;
      _shelves = shelves;
      _allPallets = all;
      _loading = false;
    });
  }

  // ── Palet olusturma ────────────────────────────────────────────────
  Future<void> _createPallet({int? shelfId, bool toFloor = false}) async {
    final codeCtrl = TextEditingController(
        text: 'P${DateTime.now().millisecondsSinceEpoch % 100000}');
    bool _floor = toFloor;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Yeni Palet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Palet kodu',
                    prefixIcon: Icon(Icons.qr_code_2_rounded)),
              ),
              const SizedBox(height: 12),
              // Zemine al seçeneği
              if (shelfId == null)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setSt(() => _floor = !_floor),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _floor,
                          onChanged: (v) => setSt(() => _floor = v ?? false),
                          activeColor: AppTheme.amber,
                        ),
                        const Icon(Icons.vertical_align_bottom_rounded,
                            size: 18, color: AppTheme.amber),
                        const SizedBox(width: 6),
                        const Text('Zemine Al',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                shelfId != null
                    ? 'Bu palet seçili rafa istiflenecek.'
                    : _floor
                        ? 'Palet zemine (yere) konulacak.'
                        : 'Palet bekleme alanına eklenecek.',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: _floor
                    ? FilledButton.styleFrom(
                        backgroundColor: AppTheme.amber,
                        foregroundColor: Colors.black)
                    : null,
                child: const Text('Oluştur')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final id = await WarehouseService.instance.createPallet(
      warehouseId: widget.warehouseId,
      shelfId: shelfId,
      floorNo: _floor ? 0 : null,
      code: codeCtrl.text.trim().isEmpty ? 'Palet' : codeCtrl.text.trim(),
    );
    if (id == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu raf dolu — palet eklenemedi')),
        );
      }
      return;
    }
    await _load();
    if (mounted) _openPallet(id);
  }

  Future<void> _openPallet(int palletId) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PalletDetailScreen(
            palletId: palletId, warehouseId: widget.warehouseId)));
    _load();
  }

  // ── Urun arama ─────────────────────────────────────────────────────
  Future<void> _searchProduct() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(warehouseId: widget.warehouseId),
    );
    if (result != null) {
      // result = palletId string -> ac
      final pid = int.tryParse(result);
      if (pid != null) _openPallet(pid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_warehouse?.name ?? 'Depo'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Ürün Ara',
            onPressed: _searchProduct,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          tabs: const [
            Tab(text: 'Harita', icon: Icon(Icons.grid_view_rounded)),
            Tab(text: 'Paletler', icon: Icon(Icons.inventory_2_rounded)),
          ],
        ),
      ),
      body: _loading
          ? const LoadingState()
          : TabBarView(
              controller: _tab,
              children: [_buildMap(), _buildPalletList()],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createPallet(),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_box_rounded),
        label: const Text('Palet'),
      ),
    );
  }

  // ── HARITA ─────────────────────────────────────────────────────────
  Widget _buildMap() {
    if (_shelves.isEmpty) {
      return const EmptyState(
        icon: Icons.grid_off_rounded,
        title: 'Raf yok',
        subtitle: 'Bu depoda tanımlı raf bulunamadı.',
      );
    }
    // Sutunlara grupla.
    final cols = <int, List<ShelfSummary>>{};
    for (final s in _shelves) {
      cols.putIfAbsent(s.shelf.columnNo, () => []).add(s);
    }
    final colNos = cols.keys.toList()..sort();

    return Column(
      children: [
        _buildLegend(),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: colNos.map((cn) {
                  final shelves = cols[cn]!
                    ..sort((a, b) =>
                        b.shelf.shelfNo.compareTo(a.shelf.shelfNo));
                  return _buildColumn(cn, shelves);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumn(int colNo, List<ShelfSummary> shelves) {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Sütun $colNo',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent)),
          ),
          const SizedBox(height: 8),
          ...shelves.map(_buildShelfCell),
        ],
      ),
    );
  }

  Widget _buildShelfCell(ShelfSummary s) {
    final color = s.isEmpty
        ? AppTheme.textTertiary
        : (s.isFull ? AppTheme.statusExpired : AppTheme.statusSafe);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _onShelfTap(s),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Raf ${s.shelf.shelfNo}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Icon(
                    s.isFull
                        ? Icons.block_rounded
                        : Icons.inventory_2_rounded,
                    size: 14,
                    color: color),
              ],
            ),
            const SizedBox(height: 6),
            // Kapasite gostergesi (dolu/bos kutucuklar)
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: List.generate(s.shelf.capacity, (i) {
                final filled = i < s.palletCount;
                return Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: filled ? color : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: color.withOpacity(0.6)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 4),
            Text('${s.palletCount}/${s.shelf.capacity}',
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Future<void> _onShelfTap(ShelfSummary s) async {
    final pallets =
        await WarehouseService.instance.getPalletsOnShelf(s.shelf.id!);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('Sütun ${s.shelf.columnNo} • Raf ${s.shelf.shelfNo}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            Text('${s.palletCount}/${s.shelf.capacity} palet dolu',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            if (pallets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Bu raf boş',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary)),
              )
            else
              ...pallets.map((p) => _palletTile(p, pop: true)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: s.isFull
                  ? null
                  : () {
                      Navigator.pop(context);
                      _createPallet(shelfId: s.shelf.id);
                    },
              icon: const Icon(Icons.add_box_rounded),
              label: Text(s.isFull
                  ? 'Raf Dolu'
                  : 'Bu Rafa Palet Ekle'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: c.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: c)),
            ),
            const SizedBox(width: 5),
            Text(t,
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          dot(AppTheme.textTertiary, 'Boş'),
          dot(AppTheme.statusSafe, 'Müsait'),
          dot(AppTheme.statusExpired, 'Dolu'),
        ],
      ),
    );
  }

  // ── PALET LISTESI ──────────────────────────────────────────────────
  Widget _buildPalletList() {
    if (_allPallets.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Palet yok',
        subtitle: 'Sağ alttaki "Palet" ile ilk paleti oluşturun.',
        action: FilledButton.icon(
          onPressed: () => _createPallet(),
          icon: const Icon(Icons.add_box_rounded),
          label: const Text('Palet Oluştur'),
          style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const SectionLabel('Tüm Paletler'),
        const SizedBox(height: 8),
        ..._allPallets.map((p) => _palletTile(p)),
      ],
    );
  }

  Widget _palletTile(PalletSummary p, {bool pop = false}) {
    final isFloor   = p.pallet.isOnFloor;
    final isWaiting = p.pallet.isUnstacked;
    final loc = p.shelf != null
        ? 'S${p.shelf!.columnNo}-R${p.shelf!.shelfNo}'
        : isFloor
            ? 'Zemin ${p.pallet.floorNo! + 1}'
            : 'Bekliyor';
    final accent = isFloor
        ? AppTheme.amber
        : (isWaiting ? AppTheme.statusWarning : AppTheme.accent);
    final locIcon = isFloor
        ? Icons.vertical_align_bottom_rounded
        : (isWaiting ? Icons.pending_rounded : Icons.place_rounded);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () {
        if (pop) Navigator.pop(context);
        _openPallet(p.pallet.id!);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(accentColor: accent),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isFloor
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.inventory_2_rounded,
                color: accent, size: 20),
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
                  Text('${p.itemTypes} çeşit • ${p.totalQty} adet',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(locIcon, size: 13, color: accent),
                  const SizedBox(width: 4),
                  Text(loc,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: accent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// ════════════════════════════════════════════════════════════════════
///  Urun arama sheet'i (barkod okut veya yaz)
/// ════════════════════════════════════════════════════════════════════
class _SearchSheet extends StatefulWidget {
  final int warehouseId;
  const _SearchSheet({required this.warehouseId});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();
  final MobileScannerController _scanner =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  List<ProductLocation>? _results;
  String? _searchedBarcode; // gercekten sorgulanan barkod (QR'dan cozulen)
  bool _searching = false;
  bool _camOpen = true;

  @override
  void dispose() {
    _scanner.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String input) async {
    if (input.trim().isEmpty) return;
    // QR (*barkod*fiyat*...) ya da duz barkod -> barkodu cikar.
    final parsed = ScanParser.parse(input);
    final barcode = parsed.barcode ?? input.trim();

    setState(() {
      _searching = true;
      _searchedBarcode = barcode;
      _ctrl.text = barcode; // kullaniciya cozulen barkodu goster
    });
    await _scanner.stop();
    final results = await WarehouseService.instance
        .findProduct(widget.warehouseId, barcode);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
      _camOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: ListView(
          controller: scroll,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Ürün Ara',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Reyon etiketini (QR) veya ürün barkodunu okutun. Etiketten '
              'okunan barkod depoda aranır.',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_camOpen)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                child: SizedBox(
                  height: 180,
                  child: MobileScanner(
                    controller: _scanner,
                    onDetect: (cap) {
                      final raw = cap.barcodes.firstOrNull?.rawValue;
                      if (raw != null) _search(raw);
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Barkod yaz / okut',
                prefixIcon: const Icon(Icons.qr_code_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => _search(_ctrl.text),
                ),
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 16),
            if (_searching)
              const Center(child: CircularProgressIndicator()),
            if (_results != null) ...[
              // Aranan barkod bilgisi
              if (_searchedBarcode != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded,
                          size: 16, color: AppTheme.textTertiary),
                      const SizedBox(width: 6),
                      Text('Aranan: $_searchedBarcode',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              if (_results!.isEmpty)
                Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 40, color: AppTheme.textTertiary),
                          SizedBox(height: 8),
                          Text('Bu ürün depoda bulunamadı',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _results = null;
                          _searchedBarcode = null;
                          _camOpen = true;
                        });
                        await _scanner.start();
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded,
                          size: 18),
                      label: const Text('Tekrar Tara'),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text('${_results!.length} konumda bulundu',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.statusSafe)),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        setState(() {
                          _results = null;
                          _searchedBarcode = null;
                          _camOpen = true;
                        });
                        await _scanner.start();
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded,
                          size: 16),
                      label: const Text('Tekrar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._results!.map(_resultTile),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultTile(ProductLocation loc) {
    final where = loc.shelf != null
        ? 'Sütun ${loc.shelf!.columnNo} • Raf ${loc.shelf!.shelfNo}'
        : 'Bekleme alanı';
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => Navigator.pop(context, loc.pallet.id.toString()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(accentColor: AppTheme.statusSafe),
        child: Row(
          children: [
            const Icon(Icons.place_rounded,
                color: AppTheme.statusSafe, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.item.productName ?? loc.item.barcode,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('$where  •  Palet: ${loc.pallet.code}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Text('${loc.item.quantity} adet',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.statusSafe)),
          ],
        ),
      ),
    );
  }
}
