import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/camera_helper.dart';
import '../../core/services/database_service.dart';
import '../../core/services/waybill_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/product_packaging.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
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

  // ── Palet resmi ──────────────────────────────────────────────────────
  Future<void> _capturePalletImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppTheme.accent),
              title: const Text('Kamera ile çek'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppTheme.accent),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_pallet?.imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.statusExpired),
                title: const Text('Resmi sil'),
                onTap: () => Navigator.pop(context, null),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    // Kullanıcı "Resmi sil" seçtiyse source null ama _pallet.imagePath dolu.
    if (source == null) {
      if (_pallet?.imagePath != null) {
        await WarehouseService.instance
            .updatePalletImage(widget.palletId, null);
        await _load();
      }
      return;
    }

    try {
      final picked = await CameraHelper.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;

      // Kalıcı dizine kopyala.
      final dir = await getApplicationDocumentsDirectory();
      final palletDir = Directory('${dir.path}/pallet_images');
      if (!palletDir.existsSync()) palletDir.createSync(recursive: true);
      final fname =
          'pallet_${widget.palletId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = '${palletDir.path}/$fname';
      await File(picked.path).copy(newPath);

      // Eski resmi sil.
      final old = _pallet?.imagePath;
      if (old != null && File(old).existsSync()) {
        try { File(old).deleteSync(); } catch (_) {}
      }

      await WarehouseService.instance
          .updatePalletImage(widget.palletId, newPath);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Palet resmi kaydedildi'),
            backgroundColor: AppTheme.statusSafe,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resim hatası: $e')),
        );
      }
    }
  }

  void _showImage() {
    final path = _pallet?.imagePath;
    if (path == null) return;
    openImageZoom(context, filePath: path, title: _pallet!.code);
  }

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
    final ctrl = TextEditingController(text: '${item.quantity}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Çıkar: ${item.productName ?? item.barcode}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mevcut: ${item.quantity} adet',
                  style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  labelText: 'Çıkarılacak adet',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      setSt(() => ctrl.text = '${item.quantity}'),
                  child: const Text('Tümü', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('İptal')),
            FilledButton(
              onPressed: () {
                final amount =
                    (int.tryParse(ctrl.text.trim()) ?? 0).clamp(0, item.quantity);
                Navigator.pop(ctx, amount);
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              child: const Text('Çıkar'),
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
              Text(
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

  // ── PALET QR ETIKETI YAZDIR ─────────────────────────────────────────
  // Paletin disina yapistirmak icin QR + kod iceren etiketi YAZICIYA
  // gonderir (sistem yazdirma diyalogu). Iki boyut: A4 / kucuk etiket.
  Future<void> _printPalletQr() async {
    final pallet = _pallet;
    if (pallet == null) return;
    final summary = _items.isEmpty
        ? null
        : _items
            .map((e) => '${e.productName ?? e.barcode}  x${e.quantity}')
            .join('\n');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded,
                      color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('QR Etiketi — ${pallet.code}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.description_rounded),
              title: const Text('A4 sayfa (büyük)'),
              subtitle: const Text('Normal yazıcı · QR + kod + ürün özeti'),
              onTap: () {
                Navigator.pop(ctx);
                _runQrPrint(() => WaybillService.instance
                    .printPalletQrA4(pallet, productSummary: summary));
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_rounded),
              title: const Text('Küçük etiket (~62×60mm)'),
              subtitle: const Text('Termal/etiket yazıcısı · QR + kod'),
              onTap: () {
                Navigator.pop(ctx);
                _runQrPrint(
                    () => WaybillService.instance.printPalletQrSmall(pallet));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _runQrPrint(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazdırılamadı: $e')),
        );
      }
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
          decoration: BoxDecoration(
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
                Center(
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
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
                if (t.note != null)
                  Text(t.note!,
                      style: TextStyle(
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
        systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.accent),
        actions: [
          // Resim göster (varsa)
          if (_pallet?.imagePath != null)
            IconButton(
              icon: const Icon(Icons.image_rounded),
              tooltip: 'Resmi Göster',
              onPressed: _showImage,
            ),
          // Resim çek/ekle
          IconButton(
            icon: Icon(_pallet?.imagePath != null
                ? Icons.add_a_photo_rounded
                : Icons.photo_camera_rounded),
            tooltip: _pallet?.imagePath != null ? 'Resmi Değiştir' : 'Resim Çek',
            onPressed: _loading ? null : _capturePalletImage,
          ),
          // Depo ici transfer
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Depo İçi Taşı',
            onPressed: _loading ? null : _transfer,
          ),
          // Transfer gecmisi + Magaza disi + Sil
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'qr') _printPalletQr();
              if (v == 'history') _showTransferHistory();
              if (v == 'external') _externalTransfer();
              if (v == 'delete') _deletePallet();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'qr',
                child: Row(children: [
                  Icon(Icons.qr_code_2_rounded,
                      size: 18, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Text('QR Etiketi Yazdır'),
                ]),
              ),
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
                // Ozet — gradient kart + istatistik seridi
                Container(
                  margin: const EdgeInsets.all(16),
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
                    border:
                        Border.all(color: AppTheme.accent.withOpacity(0.25)),
                  ),
                  child: Column(
                    children: [
                      // Konum satiri
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: (_shelf != null
                                        ? AppTheme.accent
                                        : AppTheme.amber)
                                    .withOpacity(0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                  _shelf != null
                                      ? Icons.place_rounded
                                      : Icons.pending_rounded,
                                  size: 18,
                                  color: _shelf != null
                                      ? AppTheme.accent
                                      : AppTheme.amber),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(loc,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: _shelf != null
                                          ? AppTheme.accent
                                          : AppTheme.amber)),
                            ),
                          ],
                        ),
                      ),
                      // Istatistik seridi
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.08),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(AppTheme.rLg)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            _pStat(Icons.category_rounded,
                                '${_items.length}', 'çeşit'),
                            Container(
                                width: 1,
                                height: 28,
                                color: AppTheme.accent.withOpacity(0.18)),
                            _pStat(Icons.numbers_rounded, '$_totalQty',
                                'toplam adet'),
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

  Widget _pStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
        ],
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
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: AppTheme.textTertiary)),
                    Builder(builder: (context) {
                      final pkg = parseProductPackaging(item.productName);
                      if (pkg.piecesPerCase == null ||
                          pkg.piecesPerCase! <= 0) {
                        return const SizedBox.shrink();
                      }
                      final cases =
                          (item.quantity / pkg.piecesPerCase!).toStringAsFixed(
                              item.quantity % pkg.piecesPerCase! == 0 ? 0 : 1);
                      return Text('≈ $cases koli',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.accent));
                    }),
                  ],
                ),
              ),
              Icon(Icons.more_vert_rounded,
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
        decoration: BoxDecoration(
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
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            _optionTile(
              icon: Icons.photo_camera_back_outlined,
              color: AppTheme.primary,
              title: 'Fotoğraf ve Konum',
              subtitle: 'Paletin depo fotoğrafını ve raf konumunu göster',
              value: 'photo',
            ),
            const SizedBox(height: 8),
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

    if (choice == 'photo') await _showItemPhotoAndLocation(item);
    if (choice == 'transfer') await _transferItemToPallet(item);
    if (choice == 'floor') await _putItemOnFloor(item);
    if (choice == 'remove') await _removeItem(item);
  }

  /// KAYAN PENCERE: paletin depo fotoğrafı + raftaki konumu tek bakışta.
  Future<void> _showItemPhotoAndLocation(WhPalletItem item) async {
    final photo = _pallet?.imagePath;
    final locLabel = _shelf != null
        ? 'Sütun ${_shelf!.columnNo} · Raf ${_shelf!.shelfNo}'
        : 'Zemin';
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_rounded, size: 15, color: AppTheme.accent),
                const SizedBox(width: 4),
                Text('$locLabel · ${_pallet?.code ?? ""}',
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 16),
            if (photo != null && File(photo).existsSync())
              GestureDetector(
                onTap: () => openImageZoom(
                    context, filePath: photo, title: _pallet?.code ?? ''),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.file(File(photo), fit: BoxFit.cover),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                ),
                child: Column(
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 32, color: AppTheme.textTertiary),
                    const SizedBox(height: 8),
                    Text('Bu palete henüz fotoğraf eklenmemiş',
                        style: TextStyle(
                            fontSize: 12.5, color: AppTheme.textTertiary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
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
                      style: TextStyle(
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
    final amountCtrl = TextEditingController(text: '${item.quantity}');
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
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                  onChanged: (v) => amount =
                      (int.tryParse(v.trim()) ?? amount)
                          .clamp(1, item.quantity),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: '/ ${item.quantity} adet',
                  ),
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
    int amount = item.quantity;
    final amountCtrl = TextEditingController(text: '${item.quantity}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Yere Al'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ürün, deponun "Zemin" paletine taşınacak. '
                'Kaç adet alınsın?',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
                onChanged: (v) => amount =
                    (int.tryParse(v.trim()) ?? amount)
                        .clamp(1, item.quantity),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: '/ ${item.quantity} adet',
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
    setState(() => _loading = true);

    // "Zemin" paletini bul/oluştur ve ürünü oraya taşı.
    final floorPalletId = await WarehouseService.instance
        .getOrCreateFloorPallet(widget.warehouseId);
    await WarehouseService.instance.transferItemToPallet(
      sourceItemId: item.id!,
      targetPalletId: floorPalletId,
      amount: amount,
    );
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$amount adet "Zemin" paletine alındı'),
          backgroundColor: AppTheme.statusSafe,
          duration: const Duration(seconds: 2),
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
  final _caseCtrl   = TextEditingController(); // koli bazinda giris
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
    _caseCtrl.dispose();
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
        final y = int.parse(p[2].length == 2 ? '20${p[2]}' : p[2]);
        d = DateTime(y, int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    setState(() => _expiry = d);
  }

  Future<void> _scanExpiry() async {
    final outcome = await Navigator.of(context).push<ScanOutcome>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (outcome == null || !mounted) return;
    final d = outcome.date.year == 1900 ? null : outcome.date;
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

    // SKT girilmişse SKT listesine de ekle — palet bağlantısı OLMADAN
    // (location boş; normal ürün gibi takip edilsin).
    if (_expiry != null) {
      final db = await DatabaseService.instance.database;
      await db.insert('products', {
        'name':            name ?? _barcode!,
        'barcode':         _barcode!,
        'expiry_date':     _expiry!.millisecondsSinceEpoch,
        'quantity':        qty,
        'created_at':      DateTime.now().millisecondsSinceEpoch,
        'disposal_status': 'active',
      });
    }

    if (!mounted) return;
    setState(() {
      _added++; _barcode = null; _expiry = null;
      _expiryCtrl.clear(); _qtyCtrl.text = "1"; _caseCtrl.clear(); _nameCtrl.clear();
      _busy = false;
    });
    await _scanner.start();
  }

  /// Elle barkod / ürün adı girişi (kamera olmadan).
  Future<void> _manualEntry() async {
    final bcCtrl = TextEditingController();
    final nmCtrl = TextEditingController();
    await _scanner.stop();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elle Ürün Girişi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bcCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Barkod',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nmCtrl,
              decoration: const InputDecoration(
                labelText: 'Ürün adı (opsiyonel)',
                prefixIcon: Icon(Icons.label_outline_rounded),
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
              child: const Text('Devam')),
        ],
      ),
    );

    if (ok != true) {
      await _scanner.start();
      return;
    }
    final bc = bcCtrl.text.trim();
    final nm = nmCtrl.text.trim();
    if (bc.isEmpty && nm.isEmpty) {
      await _scanner.start();
      return;
    }

    String? name = nm.isEmpty ? null : nm;
    if (name == null && bc.isNotEmpty) {
      try {
        name = await WarehouseService.instance.resolveName(bc);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _barcode = bc.isEmpty
          ? 'MANUEL-${DateTime.now().millisecondsSinceEpoch % 100000}'
          : bc;
      if (name != null) _nameCtrl.text = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
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
                    child: Text("$_added eklendi",
                        style: const TextStyle(
                            color: AppTheme.statusSafe,
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_barcode == null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                child: SizedBox(
                  height: 190,
                  child: MobileScanner(
                      controller: _scanner, onDetect: _onDetect),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard_rounded, size: 18),
                label: const Text('Elle Barkod / Ürün Adı Gir'),
              ),
            ]
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
                onChanged: (_) => setState(() {}), // paket bilgisi guncellensin
                decoration: const InputDecoration(
                  labelText: "Ürün adı",
                  prefixIcon: Icon(Icons.label_outline_rounded),
                  isDense: true,
                ),
              ),
              Builder(builder: (context) {
                final pkg = parseProductPackaging(_nameCtrl.text);
                if (!pkg.hasAny) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (pkg.piecesPerCase != null)
                        _pkgChip(
                            '1 koli = ${pkg.piecesPerCase} adet',
                            Icons.inventory_2_outlined),
                      if (pkg.palletCaseCapacity != null)
                        _pkgChip(
                            'Palet max ${pkg.palletCaseCapacity} koli',
                            Icons.view_in_ar_rounded),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              // SKT - klavye + opsiyonel OCR
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _expiryCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_DateInputFormatter()],
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
              // Adet - paket bilgisi varsa KOLI bazinda da girilebilir
              // (surekli + tusuna basmak yerine dogrudan klavyeyle).
              Builder(builder: (context) {
                final pkg = parseProductPackaging(_nameCtrl.text);
                final pieces = pkg.piecesPerCase;
                if (pieces == null || pieces <= 0) {
                  return TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Adet",
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      isDense: true,
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _caseCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final cases = int.tryParse(v.trim());
                          if (cases != null) {
                            _qtyCtrl.text = (cases * pieces).toString();
                          }
                          setState(() {});
                        },
                        decoration: const InputDecoration(
                          labelText: "Koli",
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) =>
                            setState(() => _caseCtrl.clear()),
                        decoration: const InputDecoration(
                          labelText: "Adet",
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                );
              }),
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
              child: Text(_added > 0 ? "Bitir ($_added eklendi)" : "Kapat"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pkgChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.accent),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
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
        decoration: BoxDecoration(
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
            Text('Hedef depo ve rafı seçin.',
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
              Padding(
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

/// Kullanici sadece rakam girer, otomatik "gg.aa.yyyy" formatina sokar.
/// Ornek: "15062026" -> "15.06.2026". Klavyede nokta gerekmez.
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Sadece rakamlari al, en fazla 8 hane (ggaayyyy).
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buf = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      if (i == 2 || i == 4) buf.write('.');
      buf.write(trimmed[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
