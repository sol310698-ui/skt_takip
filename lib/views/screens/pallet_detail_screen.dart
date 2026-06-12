import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/database_service.dart';
import '../../core/services/waybill_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';
import 'scanner_screen.dart';

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
    // Tum depolari ve raflarini cek.
    final allWarehouses = await WarehouseService.instance.getWarehouses();
    final currentWarehouse =
        await WarehouseService.instance.getWarehouse(widget.warehouseId);
    if (!mounted) return;

    // Transfer hedefini kullaniciya sec: (warehouseId, shelfId) cift
    // shelfId == null && warehouseId == widget.warehouseId → bekleme
    // shelfId == null && warehouseId != widget.warehouseId → diger depoda bekleme
    final result = await showModalBottomSheet<_TransferTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TransferSheet(
        currentWarehouseId: widget.warehouseId,
        currentShelfId: _pallet?.shelfId,
        allWarehouses: allWarehouses,
      ),
    );

    if (result == null) return;

    final fromShelf = _shelf;
    // Hedef raf bilgisi (aynı ya da farklı depodan)
    WhShelf? toShelf;
    Warehouse? toWarehouse;
    if (result.shelfId != null) {
      final targetShelves = await WarehouseService.instance
          .getShelves(result.warehouseId);
      toShelf = targetShelves
          .where((s) => s.id == result.shelfId)
          .firstOrNull;
    }
    toWarehouse =
        await WarehouseService.instance.getWarehouse(result.warehouseId);

    final ok = await WarehouseService.instance.movePallet(
      widget.palletId,
      result.shelfId,
      targetWarehouseId:
          result.warehouseId != widget.warehouseId ? result.warehouseId : null,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Hedef raf dolu')));
      return;
    }

    final t = WhTransfer(
      palletId: widget.palletId,
      palletCode: _pallet!.code,
      transferType: 'internal',
      fromWarehouseId: widget.warehouseId,
      fromShelfId: fromShelf?.id,
      fromWarehouseName: currentWarehouse?.name,
      fromShelfLabel: fromShelf != null
          ? 'S${fromShelf.columnNo}-R${fromShelf.shelfNo}'
          : 'Bekleme',
      toWarehouseId: result.warehouseId,
      toShelfId: toShelf?.id,
      toWarehouseName: toWarehouse?.name,
      toShelfLabel: toShelf != null
          ? 'S${toShelf.columnNo}-R${toShelf.shelfNo}'
          : 'Bekleme',
      createdAt: DateTime.now(),
      itemsSnapshot: _items,
    );
    await WarehouseService.instance.recordTransfer(t);
    await _load();

    if (!mounted) return;
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
        return false;
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () => _showItemOptions(item),
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
              const Icon(Icons.more_vert_rounded,
                  color: AppTheme.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Item için seçenek menüsü: Başka Palete Taşı, Yere Al, Çıkar.
  Future<void> _showItemOptions(WhPalletItem item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
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
            Text(item.productName ?? item.barcode,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${item.quantity} adet',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            _optionTile(
              icon: Icons.swap_horiz_rounded,
              color: AppTheme.accent,
              title: 'Başka Palete Taşı',
              subtitle: 'Seçilen palete aktar',
              value: 'transfer',
            ),
            const SizedBox(height: 8),
            _optionTile(
              icon: Icons.download_rounded,
              color: AppTheme.amber,
              title: 'Yere Al',
              subtitle: 'SKT listesine "Zemin" konumlu ürün olarak ekle',
              value: 'floor',
            ),
            const SizedBox(height: 8),
            _optionTile(
              icon: Icons.remove_circle_outline_rounded,
              color: AppTheme.statusExpired,
              title: 'Çıkar',
              subtitle: 'Paletten kaldır',
              value: 'remove',
            ),
          ],
        ),
      ),
    );

    if (choice == 'transfer') await _transferItemToPallet(item);
    if (choice == 'floor') await _putItemOnFloor(item);
    if (choice == 'remove') await _removeItem(item);
  }

  Widget _optionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => Navigator.pop(context, value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppTheme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  /// Ürünü başka palete taşı.
  Future<void> _transferItemToPallet(WhPalletItem item) async {
    // Tüm depolardaki paletleri listele (kendisi hariç).
    final allPallets =
        await WarehouseService.instance.getAllPallets(widget.warehouseId);
    // Diğer depoları da dahil et
    final otherWarehouses =
        (await WarehouseService.instance.getWarehouses())
            .where((w) => w.id != widget.warehouseId)
            .toList();
    List<PalletSummary> otherPallets = [...allPallets
        .where((p) => p.pallet.id != widget.palletId)];
    for (final w in otherWarehouses) {
      final wPallets = await WarehouseService.instance.getAllPallets(w.id!);
      otherPallets.addAll(wPallets);
    }

    if (!mounted) return;
    if (otherPallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başka palet bulunamadı')),
      );
      return;
    }

    // Adet seçimi + palet seçimi
    int amount = item.quantity;
    int? targetPalletId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Başka Palete Taşı'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Adet
                const Text('Taşınacak adet:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () =>
                          setSt(() => amount = (amount - 1).clamp(1, item.quantity)),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Container(
                      width: 50,
                      alignment: Alignment.center,
                      child: Text('$amount',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    IconButton.filledTonal(
                      onPressed: () =>
                          setSt(() => amount = (amount + 1).clamp(1, item.quantity)),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Hedef palet:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                ...otherPallets.map((p) {
                  final whName = otherWarehouses
                      .where((w) => w.id == p.pallet.warehouseId)
                      .map((w) => w.name)
                      .firstOrNull;
                  final loc = p.shelf != null
                      ? 'S${p.shelf!.columnNo}-R${p.shelf!.shelfNo}'
                      : 'Bekleme';
                  final label = whName != null
                      ? '$whName • $loc'
                      : loc;
                  return RadioListTile<int>(
                    value: p.pallet.id!,
                    groupValue: targetPalletId,
                    title: Text(p.pallet.code,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(label,
                        style: const TextStyle(fontSize: 12)),
                    onChanged: (v) => setSt(() => targetPalletId = v),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
              onPressed: targetPalletId == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent),
              child: const Text('Taşı'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || targetPalletId == null) return;

    setState(() => _loading = true);
    await WarehouseService.instance.transferItemToPallet(
      sourceItemId: item.id!,
      targetPalletId: targetPalletId!,
      amount: amount,
    );
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$amount adet taşındı'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  /// Ürünü yere al: ürün tablosuna "Zemin" konumlu kayıt ekle.
  Future<void> _putItemOnFloor(WhPalletItem item) async {
    // Kaç adet alınacak?
    int amount = item.quantity;
    final expiryCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Yere Al'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ürün SKT listesine "Zemin" konumuyla eklenecek. '
                'Son kullanma tarihini girin.',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: () =>
                        setSt(() => amount = (amount - 1).clamp(1, item.quantity)),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Container(
                    width: 50,
                    alignment: Alignment.center,
                    child: Text('$amount',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  IconButton.filledTonal(
                    onPressed: () =>
                        setSt(() => amount = (amount + 1).clamp(1, item.quantity)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expiryCtrl,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'SKT (dd.MM.yyyy)',
                  prefixIcon: Icon(Icons.event_rounded),
                  hintText: '31.12.2027',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.amber,
                  foregroundColor: Colors.black),
              child: const Text('Yere Al'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    // Tarihi parse et
    DateTime? expiry;
    try {
      final parts = expiryCtrl.text.trim().split('.');
      if (parts.length == 3) {
        expiry = DateTime(
            int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}
    expiry ??= DateTime.now().add(const Duration(days: 365));

    setState(() => _loading = true);

    // Products tablosuna ekle
    final db = await DatabaseService.instance.database;
    await db.insert('products', {
      'name': item.productName ?? item.barcode,
      'barcode': item.barcode,
      'expiry_date': expiry.millisecondsSinceEpoch,
      'quantity': amount,
      'location': 'Zemin',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'disposal_status': 'active',
    });

    // Paletten çıkar
    await WarehouseService.instance.removeItemQuantity(item.id!, amount);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$amount adet "${item.productName ?? item.barcode}" SKT listesine eklendi (Zemin)'),
          backgroundColor: AppTheme.statusSafe,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
  final _expiryCtrl = TextEditingController();
  final _qtyCtrl    = TextEditingController(text: '1');
  final _nameCtrl   = TextEditingController();

  String?   _barcode;
  DateTime? _expiry;
  bool _busy  = false;
  int  _added = 0;

  @override
  void dispose() {
    _scanner.dispose();
    _expiryCtrl.dispose();
    _qtyCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || _barcode != null) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = ScanParser.parse(raw);
    final code   = parsed.barcode ?? raw.trim();
    await _scanner.stop();
    if (parsed.expiryDate != null) {
      final d = parsed.expiryDate!;
      _expiryCtrl.text =
          '${d.day.toString().padLeft(2,"0")}.${d.month.toString().padLeft(2,"0")}.${d.year}';
    }
    String? name;
    try { name = await WarehouseService.instance.resolveName(code); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _barcode = code;
      _expiry  = parsed.expiryDate;
      if (name != null) _nameCtrl.text = name;
    });
  }

  void _parseExpiry() {
    final txt = _expiryCtrl.text.trim();
    DateTime? d;
    try {
      final p = txt.split(RegExp(r'[./\-]'));
      if (p.length == 3) {
        final y = int.parse(p[2].length == 2 ? '20\${p[2]}' : p[2]);
        d = DateTime(y, int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    setState(() => _expiry = d);
  }

  Future<void> _scanExpiry() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result == null || !mounted) return;
    final d = result.year == 1900 ? null : result;
    if (d != null) {
      _expiryCtrl.text =
          '${d.day.toString().padLeft(2,"0")}.${d.month.toString().padLeft(2,"0")}.${d.year}';
    }
    setState(() => _expiry = d);
  }

  Future<void> _confirm() async {
    if (_barcode == null) return;
    _parseExpiry();
    // SKT ve ad opsiyonel — girilmemişse de kaydedilir.
    final qty  = (int.tryParse(_qtyCtrl.text.trim()) ?? 1).clamp(1, 9999);
    final name = _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim();
    setState(() => _busy = true);

    // Depoya ekle.
    await WarehouseService.instance.addItemToPallet(
      palletId: widget.palletId,
      barcode:  _barcode!,
      quantity: qty,
      productName: name,
    );

    // SKT girilmişse SKT listesine de ekle.
    if (_expiry != null) {
      final db = await DatabaseService.instance.database;
      await db.insert('products', {
        'name':            name ?? _barcode!,
        'barcode':         _barcode!,
        'expiry_date':     _expiry!.millisecondsSinceEpoch,
        'quantity':        qty,
        'location':        'Depo / Palet',
        'created_at':      DateTime.now().millisecondsSinceEpoch,
        'disposal_status': 'active',
      });
    }

    if (!mounted) return;
    setState(() {
      _added++; _barcode = null; _expiry = null;
      _expiryCtrl.clear(); _qtyCtrl.text = "1"; _nameCtrl.clear();
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
      child: SingleChildScrollView(
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
            Row(
              children: [
                const Expanded(
                  child: Text("Ürün Ekle",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (_added > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.statusSafe.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                    child: Text("\$_added eklendi",
                        style: const TextStyle(
                            color: AppTheme.statusSafe,
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_barcode == null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                child: SizedBox(
                  height: 190,
                  child: MobileScanner(
                      controller: _scanner, onDetect: _onDetect),
                ),
              )
            else ...[
              // Barkod satiri
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: AppTheme.card(accentColor: AppTheme.accent),
                child: Row(children: [
                  const Icon(Icons.qr_code_2_rounded, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_barcode!,
                      style: const TextStyle(fontFamily: "monospace",
                          fontWeight: FontWeight.w700, fontSize: 13))),
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                    onPressed: () async {
                      setState(() { _barcode = null; _expiry = null; });
                      _expiryCtrl.clear(); _nameCtrl.clear();
                      await _scanner.start();
                    },
                    child: const Text("Değiştir", style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              // Urun adi
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: "Ürün adı",
                  prefixIcon: Icon(Icons.label_outline_rounded),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              // SKT - klavye + opsiyonel OCR
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _expiryCtrl,
                      keyboardType: TextInputType.datetime,
                      onChanged: (_) => _parseExpiry(),
                      onSubmitted: (_) => _parseExpiry(),
                      decoration: InputDecoration(
                        labelText: "SKT (gg.aa.yyyy) — opsiyonel",
                        prefixIcon: Icon(Icons.event_rounded,
                            color: _expiry != null ? AppTheme.statusSafe : null),
                        suffixIcon: _expiry != null
                            ? const Icon(Icons.check_circle_rounded,
                                color: AppTheme.statusSafe, size: 18)
                            : null,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: "OCR ile tara",
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _scanExpiry,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.textTertiary.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.document_scanner_rounded,
                            size: 20, color: AppTheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Adet
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Adet",
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _confirm,                icon: _busy
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.add_rounded),
                label: Text(_expiry != null ? "Palete Ekle + SKT Kaydet" : "Palete Ekle",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.black),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context, _added > 0),
              child: Text(_added > 0 ? "Bitir (\$_added eklendi)" : "Kapat"),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transfer hedef: hangi depo, hangi raf (null=bekleme).
class _TransferTarget {
  final int warehouseId;
  final int? shelfId;
  const _TransferTarget({required this.warehouseId, this.shelfId});
}

/// Depolar arasi transfer secim sheet'i.
/// Ust: depo secici (chip'ler). Alt: secilen depodaki raflar.
class _TransferSheet extends StatefulWidget {
  final int currentWarehouseId;
  final int? currentShelfId;
  final List<Warehouse> allWarehouses;
  const _TransferSheet({
    required this.currentWarehouseId,
    required this.currentShelfId,
    required this.allWarehouses,
  });

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late int _selectedWarehouseId;
  List<ShelfSummary> _shelves = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedWarehouseId = widget.currentWarehouseId;
    _loadShelves(_selectedWarehouseId);
  }

  Future<void> _loadShelves(int warehouseId) async {
    setState(() => _loading = true);
    final shelves =
        await WarehouseService.instance.getShelfSummaries(warehouseId);
    if (!mounted) return;
    setState(() {
      _shelves = shelves;
      _loading = false;
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
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tutac
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
            const Text('Hedef depo ve rafı seçin.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),

            // Depo secici (yatay chip'ler)
            if (widget.allWarehouses.length > 1) ...[
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: widget.allWarehouses.map((w) {
                    final selected = w.id == _selectedWarehouseId;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          if (w.id == _selectedWarehouseId) return;
                          setState(() => _selectedWarehouseId = w.id!);
                          _loadShelves(w.id!);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.accent
                                : AppTheme.surfaceAlt,
                            borderRadius:
                                BorderRadius.circular(AppTheme.rPill),
                            border: selected
                                ? null
                                : Border.all(
                                    color: AppTheme.textTertiary
                                        .withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warehouse_rounded,
                                  size: 15,
                                  color: selected
                                      ? Colors.black
                                      : AppTheme.textSecondary),
                              const SizedBox(width: 6),
                              Text(w.name,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selected
                                          ? Colors.black
                                          : AppTheme.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
            ],

            // Bekleme alanina al
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pending_rounded,
                  color: AppTheme.amber),
              title: const Text('Bekleme alanına al'),
              subtitle: Text('${_selectedWarehouseId == widget.currentWarehouseId ? "Aynı depo" : widget.allWarehouses.where((w) => w.id == _selectedWarehouseId).map((w) => w.name).firstOrNull ?? "Hedef depo"} — istiflenmemiş'),
              onTap: () => Navigator.pop(context,
                  _TransferTarget(warehouseId: _selectedWarehouseId)),
            ),
            const Divider(),

            // Raflar
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_shelves.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text('Bu depoda raf tanımlı değil',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              )
            else
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: _shelves.map((s) {
                    final full = s.isFull &&
                        !(s.shelf.id == widget.currentShelfId &&
                            _selectedWarehouseId ==
                                widget.currentWarehouseId);
                    final isCurrent = s.shelf.id ==
                            widget.currentShelfId &&
                        _selectedWarehouseId == widget.currentWarehouseId;
                    return ListTile(
                      enabled: !full && !isCurrent,
                      leading: Icon(Icons.shelves,
                          color: full
                              ? AppTheme.textTertiary
                              : AppTheme.accent),
                      title: Text(
                          'Sütun ${s.shelf.columnNo} • Raf ${s.shelf.shelfNo}'),
                      subtitle: Text(isCurrent
                          ? 'Şu anki konum'
                          : '${s.palletCount}/${s.shelf.capacity} dolu'
                              '${full ? " — DOLU" : ""}'),
                      trailing: isCurrent
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppTheme.statusSafe)
                          : null,
                      onTap: (full || isCurrent)
                          ? null
                          : () => Navigator.pop(
                                context,
                                _TransferTarget(
                                  warehouseId: _selectedWarehouseId,
                                  shelfId: s.shelf.id,
                                ),
                              ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
