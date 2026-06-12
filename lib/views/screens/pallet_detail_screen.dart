import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/waybill_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';

/// Palet detayi: icindeki urunler, ekle/cikar, transfer.
class PalletDetailScreen extends StatefulWidget {
  final int palletId;
  final int warehouseId;
  const PalletDetailScreen(
      {super.key, required this.palletId, required this.warehouseId});

  @override
  State<PalletDetailScreen> createState() => _PalletDetailScreenState();
}

class _PalletDetailScreenState extends State<PalletDetailScreen> {
  WhPallet? _pallet;
  List<WhPalletItem> _items = [];
  WhShelf? _shelf;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pallet = await WarehouseService.instance.getPallet(widget.palletId);
    final items =
        await WarehouseService.instance.getPalletItems(widget.palletId);
    WhShelf? shelf;
    if (pallet?.shelfId != null) {
      final shelves =
          await WarehouseService.instance.getShelves(widget.warehouseId);
      shelf = shelves.where((s) => s.id == pallet!.shelfId).firstOrNull;
    }
    if (!mounted) return;
    setState(() {
      _pallet = pallet;
      _items = items;
      _shelf = shelf;
      _loading = false;
    });
  }

  int get _totalQty => _items.fold(0, (s, i) => s + i.quantity);

  // ── Urun ekle ──────────────────────────────────────────────────────
  Future<void> _addItem() async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddItemSheet(palletId: widget.palletId),
    );
    if (res == true) _load();
  }

  // ── Urun cikar ─────────────────────────────────────────────────────
  Future<void> _removeItem(WhPalletItem item) async {
    int amount = 1;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Çıkar: ${item.productName ?? item.barcode}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mevcut: ${item.quantity} adet',
                  style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: () =>
                        setSt(() => amount = (amount - 1).clamp(1, item.quantity)),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Container(
                    width: 60,
                    alignment: Alignment.center,
                    child: Text('$amount',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  IconButton.filledTonal(
                    onPressed: () =>
                        setSt(() => amount = (amount + 1).clamp(1, item.quantity)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, amount),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              child: Text('$amount Adet Çıkar'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result > 0) {
      await WarehouseService.instance
          .removeItemQuantity(item.id!, result);
      _load();
    }
  }

  // ── Depo ici transfer ───────────────────────────────────────────────
  Future<void> _transfer() async {
    final shelves =
        await WarehouseService.instance.getShelfSummaries(widget.warehouseId);
    final warehouse = await WarehouseService.instance
        .getWarehouse(widget.warehouseId);
    if (!mounted) return;

    final target = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Paleti Taşı',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Hedef rafı seçin (dolu raflar pasiftir).',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.pending_rounded, color: AppTheme.amber),
              title: const Text('Bekleme alanına al'),
              subtitle: const Text('Raftan çıkar, istiflenmemiş yap'),
              onTap: () => Navigator.pop(context, -1),
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: shelves.map((s) {
                  final full = s.isFull && s.shelf.id != _pallet?.shelfId;
                  final isCurrent = s.shelf.id == _pallet?.shelfId;
                  return ListTile(
                    enabled: !full && !isCurrent,
                    leading: Icon(Icons.shelves,
                        color: full ? AppTheme.textTertiary : AppTheme.accent),
                    title: Text('Sütun ${s.shelf.columnNo} • Raf ${s.shelf.shelfNo}'),
                    subtitle: Text(isCurrent
                        ? 'Şu anki konum'
                        : '${s.palletCount}/${s.shelf.capacity} dolu${full ? " — DOLU" : ""}'),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle_rounded, color: AppTheme.statusSafe)
                        : null,
                    onTap: (full || isCurrent)
                        ? null
                        : () => Navigator.pop(context, s.shelf.id),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );

    if (target == null) return;
    final targetShelf = target == -1 ? null : target;

    // Mevcut raf bilgisini al (transfer kaydı için)
    final fromShelf = _shelf;
    final WhShelf? toShelf = targetShelf != null
        ? shelves.firstWhere((s) => s.shelf.id == targetShelf).shelf
        : null;

    final ok = await WarehouseService.instance
        .movePallet(widget.palletId, targetShelf);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hedef raf dolu')));
      return;
    }

    // Transfer kaydet
    final t = WhTransfer(
      palletId: widget.palletId,
      palletCode: _pallet!.code,
      transferType: 'internal',
      fromWarehouseId: widget.warehouseId,
      fromShelfId: fromShelf?.id,
      fromWarehouseName: warehouse?.name,
      fromShelfLabel: fromShelf != null
          ? 'S${fromShelf.columnNo}-R${fromShelf.shelfNo}'
          : 'Bekleme',
      toWarehouseId: widget.warehouseId,
      toShelfId: toShelf?.id,
      toWarehouseName: warehouse?.name,
      toShelfLabel: toShelf != null
          ? 'S${toShelf.columnNo}-R${toShelf.shelfNo}'
          : 'Bekleme',
      createdAt: DateTime.now(),
      itemsSnapshot: _items,
    );
    await WarehouseService.instance.recordTransfer(t);
    await _load();

    if (!mounted) return;
    // Irsaliye onerisi
    _offerWaybill(t);
  }

  // ── Magaza disi transfer ────────────────────────────────────────────
  Future<void> _externalTransfer() async {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final warehouse = await WarehouseService.instance
        .getWarehouse(widget.warehouseId);

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mağaza Dışı Sevk'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bu palet mağazadan çıkacak. Alıcı bilgilerini girin; '
                'irsaliye PDF oluşturulacak.',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alıcı adı / Mağaza *',
                  prefixIcon: Icon(Icons.store_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Adres',
                  prefixIcon: Icon(Icons.location_on_rounded),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Not (opsiyonel)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral),
            child: const Text('Sevk Et & İrsaliye'),
          ),
        ],
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    final t = WhTransfer(
      palletId: widget.palletId,
      palletCode: _pallet!.code,
      transferType: 'external',
      fromWarehouseId: widget.warehouseId,
      fromShelfId: _shelf?.id,
      fromWarehouseName: warehouse?.name,
      fromShelfLabel: _shelf != null
          ? 'S${_shelf!.columnNo}-R${_shelf!.shelfNo}'
          : 'Bekleme',
      toExternalName: nameCtrl.text.trim(),
      toExternalAddress: addrCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      createdAt: DateTime.now(),
      itemsSnapshot: _items,
    );

    await WarehouseService.instance.recordTransfer(t);
    // Dış transfer: paleti bekleme alanına al (raftan çıkar)
    await WarehouseService.instance.movePallet(widget.palletId, null);
    await _load();

    if (!mounted) return;
    _offerWaybill(t);
  }

  // ── Irsaliye onerisi & PDF ──────────────────────────────────────────
  void _offerWaybill(WhTransfer t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Transfer kaydedildi'),
        backgroundColor: AppTheme.statusSafe,
        action: SnackBarAction(
          label: 'İrsaliye',
          textColor: Colors.white,
          onPressed: () => _generateAndShareWaybill(t),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _generateAndShareWaybill(WhTransfer t) async {
    setState(() => _loading = true);
    try {
      final path = await WaybillService.instance.generateWaybill(
        pallet: _pallet!,
        items: t.itemsSnapshot.isNotEmpty ? t.itemsSnapshot : _items,
        transfer: t,
      );
      await WaybillService.instance.sharePdf(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Gecmis transferler listesi
  Future<void> _showTransferHistory() async {
    final transfers =
        await WarehouseService.instance.getTransfers(widget.palletId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: ListView(
            controller: scroll,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: AppTheme.textTertiary,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('Transfer Geçmişi (${transfers.length})',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (transfers.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Henüz transfer kaydı yok',
                        style:
                            TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                ...transfers.map((t) => _transferTile(t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _transferTile(WhTransfer t) {
    final isExt = t.transferType == 'external';
    final from = t.fromShelfLabel ?? 'Bekleme';
    final to = isExt
        ? (t.toExternalName ?? 'Dış')
        : (t.toShelfLabel ?? 'Bekleme');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(
          accentColor: isExt ? AppTheme.coral : AppTheme.accent),
      child: Row(
        children: [
          Icon(
              isExt ? Icons.local_shipping_rounded : Icons.swap_horiz_rounded,
              color: isExt ? AppTheme.coral : AppTheme.accent,
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$from  →  $to',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text(
                  '${t.createdAt.day.toString().padLeft(2, '0')}.${t.createdAt.month.toString().padLeft(2, '0')}.${t.createdAt.year}  •  '
                  '${t.itemsSnapshot.length} çeşit',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
                if (t.note != null)
                  Text(t.note!,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded,
                color: AppTheme.coral),
            tooltip: 'İrsaliye',
            onPressed: () => _generateAndShareWaybill(t),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePallet() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paleti Sil'),
        content: Text(
            '${_pallet?.code ?? "Palet"} ve içindeki tüm ürünler silinecek. '
            'Emin misiniz?'),
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
      await WarehouseService.instance.deletePallet(widget.palletId);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = _shelf != null
        ? 'Sütun ${_shelf!.columnNo} • Raf ${_shelf!.shelfNo}'
        : 'Bekleme alanı';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_pallet?.code ?? 'Palet'),
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.black,
        actions: [
          // Depo ici transfer
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Depo İçi Taşı',
            onPressed: _loading ? null : _transfer,
          ),
          // Transfer gecmisi + Magaza disi + Sil
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'history') _showTransferHistory();
              if (v == 'external') _externalTransfer();
              if (v == 'delete') _deletePallet();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'external',
                child: Row(children: [
                  Icon(Icons.local_shipping_rounded,
                      size: 18, color: AppTheme.coral),
                  SizedBox(width: 8),
                  Text('Mağaza Dışı Sevk'),
                ]),
              ),
              PopupMenuItem(
                value: 'history',
                child: Row(children: [
                  Icon(Icons.history_rounded,
                      size: 18, color: AppTheme.accent),
                  SizedBox(width: 8),
                  Text('Transfer Geçmişi'),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppTheme.statusExpired),
                  SizedBox(width: 8),
                  Text('Paleti Sil'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const LoadingState()
          : Column(
              children: [
                // Ozet
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.card(accentColor: AppTheme.accent),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                    _shelf != null
                                        ? Icons.place_rounded
                                        : Icons.pending_rounded,
                                    size: 16,
                                    color: _shelf != null
                                        ? AppTheme.accent
                                        : AppTheme.amber),
                                const SizedBox(width: 6),
                                Text(loc,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _shelf != null
                                            ? AppTheme.accent
                                            : AppTheme.amber)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                                '${_items.length} çeşit • $_totalQty toplam adet',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? EmptyState(
                          icon: Icons.add_shopping_cart_rounded,
                          title: 'Palet boş',
                          subtitle:
                              'Barkod okutarak ürün ekleyin. Tek çeşit ya da '
                              'karışık ürün koyabilirsiniz.',
                          action: FilledButton.icon(
                            onPressed: _addItem,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Ürün Ekle'),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.black),
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _itemTile(_items[i]),
                        ),
                ),
              ],
            ),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addItem,
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ürün Ekle'),
            ),
    );
  }

  Widget _itemTile(WhPalletItem item) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.statusExpired.withOpacity(0.2),
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        child: const Icon(Icons.remove_circle_outline_rounded,
            color: AppTheme.statusExpired),
      ),
      confirmDismiss: (_) async {
        _removeItem(item);
        return false; // dialog hallediyor
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () => _removeItem(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${item.quantity}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppTheme.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.productName ?? 'Bilinmeyen ürün',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(item.barcode,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              const Icon(Icons.remove_circle_outline_rounded,
                  color: AppTheme.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  Urun ekleme sheet'i (barkod okut + adet)
/// ════════════════════════════════════════════════════════════════════
class _AddItemSheet extends StatefulWidget {
  final int palletId;
  const _AddItemSheet({required this.palletId});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final MobileScannerController _scanner =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  final _qtyCtrl = TextEditingController(text: '1');
  String? _barcode;
  bool _busy = false;
  int _added = 0;

  @override
  void dispose() {
    _scanner.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || _barcode != null) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final code = ScanParser.parse(raw).barcode ?? raw.trim();
    await _scanner.stop();
    // Isim ekleme aninda servis icinde dizin/OFF'tan cozulur.
    setState(() => _barcode = code);
  }

  Future<void> _confirm() async {
    if (_barcode == null) return;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    setState(() => _busy = true);
    await WarehouseService.instance.addItemToPallet(
      palletId: widget.palletId,
      barcode: _barcode!,
      quantity: qty < 1 ? 1 : qty,
    );
    setState(() {
      _added++;
      _barcode = null;

      _qtyCtrl.text = '1';
      _busy = false;
    });
    await _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 20),
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
          Row(
            children: [
              const Expanded(
                child: Text('Ürün Ekle',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (_added > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.statusSafe.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text('$_added eklendi',
                      style: const TextStyle(
                          color: AppTheme.statusSafe,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_barcode == null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              child: SizedBox(
                height: 200,
                child: MobileScanner(
                    controller: _scanner, onDetect: _onDetect),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.card(accentColor: AppTheme.accent),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded,
                      color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_barcode!,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700)),
                        const Text('Adet girip onaylayın',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Adet:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _barcode = null);
                            await _scanner.start();
                          },
                    child: const Text('Yeniden Tara'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _confirm,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Palete Ekle'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.black),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context, _added > 0),
            child: Text(_added > 0 ? 'Bitir ($_added eklendi)' : 'Kapat'),
          ),
        ],
      ),
    );
  }
}
