import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/camera_helper.dart';
import '../../core/services/database_service.dart';
import '../../core/services/flow_prefs.dart';
import '../../core/services/location_reveal_prefs.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/repositories/barcode_directory_repository.dart';
import '../../core/services/waybill_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/product_packaging.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/location_reveal.dart';
import '../widgets/ui_kit.dart';
import 'barcode_detail_screen.dart';
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

  // ── Urun ekle — TAM SAYFA akilli ekran (sheet degil, fragment gibi) ─
  Future<void> _addItem() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AddItemScreen(
          palletId: widget.palletId,
          warehouseId: widget.warehouseId,
          palletCode: _pallet?.code ?? 'Palet',
        ),
      ),
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
      // ── FEFO AKILLI CIKARMA: bagli SKT partileri varsa once sor. ──
      final batches =
          await WarehouseService.instance.linkedBatches(item.id!);
      int? preferredId;
      if (batches.length > 1) {
        if (!mounted) return;
        final picked = await _pickBatchForRemoval(item, result, batches);
        if (picked == null) return; // iptal
        preferredId = picked;
      }
      // Partilerden dus (FEFO / secilen once), sonra kalemden dus.
      final consumed = await WarehouseService.instance
          .consumeLinkedBatches(item.id!, result, preferredId: preferredId);
      await WarehouseService.instance
          .removeItemQuantity(item.id!, result);
      await _load();
      if (!mounted) return;
      // Ozet: hangi parti(ler)den dustu.
      String detail = '';
      if (consumed.isNotEmpty) {
        final parts = consumed.map((c) {
          final row = c['row'] as Map;
          final d = DateTime.fromMillisecondsSinceEpoch(
              row['expiry_date'] as int);
          return '${c['taken']}× '
              '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
        }).join(', ');
        detail = ' ($parts)';
      }
      // GERİ AL: kalem + parti dusumlerini birlikte geri alir.
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '$result adet çıkarıldı$detail: ${item.productName ?? item.barcode}'),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Geri Al',
            textColor: AppTheme.accent,
            onPressed: () async {
              final newItemId =
                  await WarehouseService.instance.addItemToPallet(
                palletId: widget.palletId,
                barcode: item.barcode,
                quantity: result,
                productName: item.productName,
              );
              await WarehouseService.instance.restoreConsumedBatches(
                  consumed,
                  relinkItemId: newItemId);
              _load();
            },
          ),
        ),
      );
    }
  }

  /// FEFO PARTI SECICI: birden fazla tarihli parti varsa hangi partiden
  /// cikarilacagini sorar. EN YAKIN tarih onerilir; kullanici uzak tarihi
  /// secerse acikca uyarilir. Secim yeterli degilse kalan adet otomatik
  /// FEFO sirayla diger partilerden devam eder.
  Future<int?> _pickBatchForRemoval(WhPalletItem item, int amount,
      List<Map<String, Object?>> batches) async {
    int selected = batches.first['id'] as int; // varsayilan: en yakin
    final nearestId = selected;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final warnFar = selected != nearestId;
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, 20 + MediaQuery.of(ctx).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                        color: AppTheme.textTertiary,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text('$amount adet hangi partiden çıksın?',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    'FEFO: önce en yakın tarihli çıkarılmalı. Seçilen parti '
                    'yetmezse kalan otomatik sıradaki partiden düşülür.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 12),
                for (final b in batches)
                  Builder(builder: (_) {
                    final id = b['id'] as int;
                    final d = DateTime.fromMillisecondsSinceEpoch(
                        b['expiry_date'] as int);
                    final q = (b['quantity'] as int?) ?? 0;
                    final days =
                        d.difference(DateTime.now()).inDays;
                    final c = days < 0
                        ? AppTheme.statusExpired
                        : days <= 7
                            ? AppTheme.statusCritical
                            : days <= 30
                                ? AppTheme.statusWarning
                                : AppTheme.statusSafe;
                    final isSel = selected == id;
                    final isNearest = id == nearestId;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setSt(() => selected = id),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSel
                              ? c.withOpacity(0.12)
                              : AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isSel
                                  ? c
                                  : AppTheme.hairline,
                              width: isSel ? 1.6 : 1),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                isSel
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 20,
                                color: isSel
                                    ? c
                                    : AppTheme.textTertiary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: c)),
                                  Text(
                                      '$q adet · '
                                      '${days < 0 ? '${-days} gün geçti' : '$days gün kaldı'}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                            if (isNearest)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.statusSafe.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.rPill),
                                ),
                                child: const Text('ÖNERİLEN · FEFO',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.statusSafe)),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                // UZAK TARIH UYARISI.
                if (warnFar)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.statusExpired.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: AppTheme.statusExpired),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Dikkat: daha YAKIN tarihli parti dururken '
                              'uzak tarihliyi çıkarıyorsun!',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.statusExpired)),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('İptal'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, selected),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.statusExpired),
                        child: const Text('Çıkar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Barkodla urun bul & cikar ───────────────────────────────────────
  // Buyuk paletlerde urunu listede aramak yerine barkodu okut/yaz -> palette
  // eslesen urun bulunur ve cikarma penceresi acilir. El terminali (klavye
  // gibi davranan barkod okuyucu) ve elle giris ile calisir.
  Future<void> _findAndRemoveByBarcode() async {
    final ctrl = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barkodla Ürün Bul'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Barkodu okutun ya da yazın; paletteki ürün bulunup çıkarma açılır.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              decoration: const InputDecoration(
                labelText: 'Barkod',
                prefixIcon: Icon(Icons.qr_code_rounded),
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
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Bul'),
          ),
        ],
      ),
    );
    if (entered == null || entered.isEmpty || !mounted) return;
    final norm = ScanParser.parse(entered).barcode ?? entered.trim();
    final matches = _items
        .where((e) => e.barcode == norm || e.barcode == entered.trim())
        .toList();
    if (matches.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bu palette "$norm" barkodlu ürün yok')),
        );
      }
      return;
    }
    if (matches.length == 1) {
      _removeItem(matches.first);
      return;
    }
    // Ayni barkoddan birden fazla kayit (farkli SKT/parti) -> secim.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('${matches.length} eşleşme — birini seçin',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            for (final m in matches)
              ListTile(
                leading: const Icon(Icons.inventory_2_rounded),
                title: Text(m.productName ?? m.barcode),
                subtitle: Text('${m.quantity} adet'),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeItem(m);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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
    final result = await Navigator.of(context).push<_TransferTarget>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TransferScreen(
          currentWarehouseId: widget.warehouseId,
          currentShelfId: _pallet?.shelfId,
          allWarehouses: allWarehouses,
          palletCode: _pallet?.code ?? 'Palet',
        ),
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading
          ? const SkeletonList()
          : Column(
              children: [
                _hero(),
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
                          padding: EdgeInsets.fromLTRB(16, 4, 16,
                              MediaQuery.of(context).padding.bottom + 90),
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

  /// ── GRADYAN HERO: palet kodu + aksiyon ikonları + konum & özet ──
  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    final onShelf = _shelf != null;
    final locLabel = onShelf
        ? 'Sütun ${_shelf!.columnNo} · Raf ${_shelf!.shelfNo}'
        : 'Bekleme alanı';
    final hasPhoto =
        _pallet?.imagePath != null && File(_pallet!.imagePath!).existsSync();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 16),
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
        children: [
          // Üst bar: geri + kod + aksiyon ikonları.
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.black),
              ),
              Expanded(
                child: Text(_pallet?.code ?? 'Palet',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.black)),
              ),
              IconButton(
                icon: Icon(
                    hasPhoto
                        ? Icons.add_a_photo_rounded
                        : Icons.photo_camera_rounded,
                    color: Colors.black),
                tooltip: hasPhoto ? 'Resmi Değiştir' : 'Resim Çek',
                onPressed: _capturePalletImage,
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.black),
                tooltip: 'Barkodla Ürün Bul/Çıkar',
                onPressed: _findAndRemoveByBarcode,
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded,
                    color: Colors.black),
                tooltip: 'Depo İçi Taşı',
                onPressed: _transfer,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: Colors.black),
                onSelected: (v) {
                  if (v == 'qr') _printPalletQr();
                  if (v == 'history') _showTransferHistory();
                  if (v == 'external') _externalTransfer();
                  if (v == 'delete') _deletePallet();
                  if (v == 'image' && hasPhoto) _showImage();
                },
                itemBuilder: (_) => [
                  if (hasPhoto)
                    const PopupMenuItem(
                      value: 'image',
                      child: Row(children: [
                        Icon(Icons.image_rounded,
                            size: 18, color: AppTheme.accent),
                        SizedBox(width: 8),
                        Text('Resmi Göster'),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'qr',
                    child: Row(children: [
                      Icon(Icons.qr_code_2_rounded,
                          size: 18, color: AppTheme.primary),
                      SizedBox(width: 8),
                      Text('QR Etiketi Yazdır'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'external',
                    child: Row(children: [
                      Icon(Icons.local_shipping_rounded,
                          size: 18, color: AppTheme.coral),
                      SizedBox(width: 8),
                      Text('Mağaza Dışı Sevk'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(children: [
                      Icon(Icons.history_rounded,
                          size: 18, color: AppTheme.accent),
                      SizedBox(width: 8),
                      Text('Transfer Geçmişi'),
                    ]),
                  ),
                  const PopupMenuItem(
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
          const SizedBox(height: 6),
          // Konum + özet paneli (tek kart, cam efektli).
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Column(
              children: [
                // Konum satırı + hızlı foto küçük görsel.
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                            onShelf
                                ? Icons.place_rounded
                                : Icons.pending_rounded,
                            size: 18,
                            color: Colors.black),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(locLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Colors.black)),
                      ),
                      if (hasPhoto)
                        GestureDetector(
                          onTap: _showImage,
                          child: Container(
                            width: 40,
                            height: 40,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.black.withOpacity(0.3),
                                  width: 1.5),
                            ),
                            child: Image.file(File(_pallet!.imagePath!),
                                fit: BoxFit.cover),
                          ),
                        ),
                    ],
                  ),
                ),
                // İstatistik şeridi.
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.10),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(AppTheme.rMd)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      _heroStat(Icons.category_rounded,
                          '${_items.length}', 'çeşit'),
                      Container(
                          width: 1,
                          height: 28,
                          color: Colors.black.withOpacity(0.18)),
                      _heroStat(Icons.numbers_rounded, '$_totalQty',
                          'toplam adet'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.black),
              const SizedBox(width: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
            ],
          ),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.black87)),
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

  /// Item için seçenek menüsü — ÜRÜNÜN TAM ERİŞİM NOKTASI.
  /// Menü açılmadan önce ürünün bağlamı yüklenir (yerel foto, tanımlı SKT,
  /// reyon konumu) ve başlıkta gösterilir; buradan ürünle ilgili HER ŞEYE
  /// ulaşılır: Ürün Sayfası (hub), reyon canlandırması, foto+konum, taşı,
  /// yere al, çıkar.
  Future<void> _showItemOptions(WhPalletItem item) async {
    // ── BAGLAM YUKLE (hizli yerel sorgular) ──
    String? photo;
    try {
      final repo = BarcodeDirectoryRepository(
          BarcodeDirectoryDataSource(DatabaseService.instance));
      final pth = await repo.getLocalImage(item.barcode);
      if (pth != null && pth.isNotEmpty && File(pth).existsSync()) {
        photo = pth;
      }
    } catch (_) {}
    DateTime? sktNearest;
    int sktCount = 0;
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query('products',
          columns: ['expiry_date'],
          where: "barcode = ? AND disposal_status = 'active'",
          whereArgs: [item.barcode],
          orderBy: 'expiry_date ASC');
      sktCount = rows.length;
      if (rows.isNotEmpty) {
        sktNearest = DateTime.fromMillisecondsSinceEpoch(
            rows.first['expiry_date'] as int);
      }
    } catch (_) {}
    ShelfLocationHit? shelfHit;
    try {
      shelfHit =
          await ShelfLayoutService.instance.locateBarcode(item.barcode);
    } catch (_) {}
    if (!mounted) return;

    // SKT cip rengi (kalan gune gore).
    Color? sktColor;
    String? sktLabel;
    if (sktNearest != null) {
      final days = sktNearest.difference(DateTime.now()).inDays;
      sktColor = days < 0
          ? AppTheme.statusExpired
          : days <= 7
              ? AppTheme.statusCritical
              : days <= 30
                  ? AppTheme.statusWarning
                  : AppTheme.statusSafe;
      final d = sktNearest;
      sktLabel =
          'SKT ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'
          '${days < 0 ? ' · ${-days}g geçti' : ' · ${days}g'}'
          '${sktCount > 1 ? ' · $sktCount kayıt' : ''}';
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
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
                // FOTO (varsa) — dokununca tam ekran; yoksa adet kutusu.
                photo != null
                    ? GestureDetector(
                        onTap: () => openImageZoom(context,
                            filePath: photo,
                            title: item.productName ?? item.barcode),
                        child: Container(
                          width: 52,
                          height: 52,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppTheme.accent.withOpacity(0.5)),
                          ),
                          child:
                              Image.file(File(photo), fit: BoxFit.cover),
                        ),
                      )
                    : Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${item.quantity}',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.accent)),
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName ?? item.barcode,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Text('${item.quantity} adet · ${item.barcode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 11.5,
                              fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ],
            ),
            // BAGLAM CIPLERI: tanimli SKT + reyon konumu bir bakista.
            if (sktLabel != null || shelfHit != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (sktLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: sktColor!.withOpacity(0.14),
                        borderRadius:
                            BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_rounded,
                              size: 13, color: sktColor),
                          const SizedBox(width: 4),
                          Text(sktLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: sktColor)),
                        ],
                      ),
                    ),
                  if (shelfHit != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.14),
                        borderRadius:
                            BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shelves,
                              size: 13, color: AppTheme.primary),
                          const SizedBox(width: 4),
                          Text(
                              '${shelfHit!.unitName} · S${shelfHit!.section}·R${shelfHit!.row}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // ── HER SEYE ERISIM: urun hub sayfasi ──
            _optionTile(
              icon: Icons.dashboard_rounded,
              color: AppTheme.statusSafe,
              title: 'Ürün Sayfası',
              subtitle:
                  'Foto, tanımlı SKT, reyon/depo konumları ve canlandırmalar — her şey tek sayfada',
              value: 'product',
            ),
            if (shelfHit != null) ...[
              const SizedBox(height: 8),
              _optionTile(
                icon: Icons.travel_explore_rounded,
                color: AppTheme.primary,
                title: 'Reyonda Göster',
                subtitle:
                    '${shelfHit!.unitName} · Sütun ${shelfHit!.section} · Raf ${shelfHit!.row} — canlandır',
                value: 'shelf',
              ),
            ],
            const SizedBox(height: 8),
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
      ),
    );

    if (choice == 'product') await _openProductHub(item);
    if (choice == 'shelf' && shelfHit != null) {
      _playItemShelfReveal(item, shelfHit!);
    }
    if (choice == 'photo') await _showItemPhotoAndLocation(item);
    if (choice == 'transfer') await _transferItemToPallet(item);
    if (choice == 'floor') await _putItemOnFloor(item);
    if (choice == 'remove') await _removeItem(item);
  }

  /// ÜRÜN SAYFASI: barkod detay hub'ına git (foto hero + SKT + reyon/depo
  /// konumları + canlandırmalar — v132). Dizin kaydı yoksa geçici giriş.
  Future<void> _openProductHub(WhPalletItem item) async {
    BarcodeEntry? entry;
    try {
      final repo = BarcodeDirectoryRepository(
          BarcodeDirectoryDataSource(DatabaseService.instance));
      entry = await repo.findEntryByBarcode(item.barcode);
    } catch (_) {}
    entry ??= BarcodeEntry(
      barcode: item.barcode,
      productName: item.productName ?? item.barcode,
      importedAt: DateTime.now(),
    );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BarcodeDetailScreen(entry: entry!)));
  }

  /// Reyon canlandırması (menüden, kullanıcı isteğiyle).
  void _playItemShelfReveal(WhPalletItem item, ShelfLocationHit hit) {
    if (!LocationRevealPrefs.instance.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Konum canlandırması Ayarlar > Görünüm’den kapalı.')));
      return;
    }
    showLocationFlythrough(
      context,
      title: hit.unitName,
      cols: hit.cols,
      rows: hit.rows,
      targetCol: hit.section,
      targetRow: hit.row,
      subtitle: 'Sütun ${hit.section} · Raf ${hit.row}',
      productName: hit.productName ?? item.productName,
      photoPath: hit.photoPath,
      allAisles: hit.allUnitNames,
      targetAisleIndex: hit.unitIndex,
      shelfProducts: hit.shelf
          .map((e) => RevealShelfProduct(
                name: e.name,
                photoPath: e.photoPath,
                sectionNo: e.sectionNo,
                isTarget: e.isTarget,
              ))
          .toList(),
    );
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
///  ÜRÜN EKLEME — TAM SAYFA AKILLI EKRAN ("fragment" gibi, sheet değil)
/// ────────────────────────────────────────────────────────────────────
///  İki giriş yolu (üstte segment):
///   • TARA  — kamera ile barkod okut (eski davranış).
///   • ARA   — VERİTABANI SORGUSU: barkod dizininde ad / barkod / stok
///             kodu ile canlı arama; sonuçtan seçince form dolar.
///  AKILLI katman (ürün seçilince):
///   • Dizinden ad + stok kodu otomatik gelir.
///   • Ürün BU depoda başka nerede varsa (palet + sütun·raf + adet)
///     çipler halinde gösterilir; aynı palete ekleme "miktar birleşir"
///     uyarısı verir.
///   • Ad içindeki paket kalıbı (*12, PLT-72) çözümlenip koli bazlı
///     giriş açılır (eski davranış korunur).
/// ════════════════════════════════════════════════════════════════════
class _AddItemScreen extends StatefulWidget {
  final int palletId;
  final int warehouseId;
  final String palletCode;
  const _AddItemScreen({
    required this.palletId,
    required this.warehouseId,
    required this.palletCode,
  });
  @override
  State<_AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<_AddItemScreen> {
  final MobileScannerController _scanner =
      MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  final _expiryCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _caseCtrl = TextEditingController(); // koli bazinda giris
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  late final BarcodeDirectoryRepository _dirRepo =
      BarcodeDirectoryRepository(
          BarcodeDirectoryDataSource(DatabaseService.instance));

  int _mode = 0; // 0 = TARA (kamera), 1 = ARA (veritabani)
  String? _barcode;
  String? _stockCode;
  DateTime? _expiry;
  bool _busy = false;
  int _added = 0;

  // Canli arama durumu.
  List<BarcodeEntry> _results = [];
  bool _searching = false;
  int _searchSeq = 0; // gec gelen sonuclari at

  // Akilli konum bilgisi: urun bu depoda baska nerede?
  List<ProductLocation> _existingLocs = [];

  // ── SIRKET UYGULAMASI ENTEGRASYONU ───────────────────────────────
  // Barkod okutuldugunda adi bilinmiyorsa sirket uygulamasina gecilir;
  // orada okutulunca erisilebilirlik servisi urun adi/stok kodunu okur
  // ve systemPriceStream ile buraya gonderir. Gelen veri forma ve
  // barkod dizinine yazilir (bir dahakine sormaz).
  bool _companyMode = false;
  bool _serviceOn = false;
  StreamSubscription<SystemPriceSnapshot>? _liveSub;
  String? _awaitingBarcode;

  @override
  void initState() {
    super.initState();
    _initCompanyFlow();
  }

  Future<void> _initCompanyFlow() async {
    try {
      await FlowPrefs.instance.load();
    } catch (_) {}
    final on = await PriceCheckChannel.isServiceRunning();
    if (!mounted) return;
    setState(() {
      _companyMode = FlowPrefs.instance.autoFlow;
      _serviceOn = on;
    });
    _liveSub = PriceCheckChannel.systemPriceStream.listen(_onSystemData);
  }

  /// Sirket uygulamasindan urun bilgisi geldi — forma ve dizine yaz.
  Future<void> _onSystemData(SystemPriceSnapshot sys) async {
    final name = sys.productName?.trim();
    if (name == null || name.isEmpty) return;
    if (_looksLikeStaticFormLabel(name)) return;
    // Hangi barkoda ait? Bekledigimiz varsa o, yoksa sistemin verdigi.
    final code = _awaitingBarcode ?? sys.barcode?.trim() ?? _barcode;
    if (code == null || code.isEmpty) return;
    // Form baska bir urune gectiyse yazma.
    if (_barcode != null && _barcode != code) return;

    final sc = sys.stockCode?.trim();
    try {
      await BarcodeDirectoryDataSource(DatabaseService.instance).importAll([
        BarcodeEntry(
          barcode: code,
          productName: name,
          stockCode: (sc == null || sc.isEmpty) ? null : sc,
          importedAt: DateTime.now(),
          source: BarcodeSource.screen,
        )
      ]);
    } catch (_) {}
    _awaitingBarcode = null;
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = name;
      if (sc != null && sc.isNotEmpty) _stockCode = sc;
    });
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Şirket verisi alındı: $name'),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.statusSafe,
    ));
  }

  bool _looksLikeStaticFormLabel(String line) {
    final lower = line.trim().toLowerCase();
    const staticPhrases = [
      'denetim formu',
      'kontrol formu',
      'fiyat kontrol',
      'fiyat kontrolü',
      'ürün denetim',
      'urun denetim',
    ];
    return staticPhrases.any((p) => lower == p || lower.startsWith('$p '));
  }

  /// Sirket uygulamasina gec — [code] orada okutulacak.
  Future<void> _goToCompanyApp(String code) async {
    _awaitingBarcode = code;
    if (!_serviceOn) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Erişilebilirlik servisi kapalı'),
          content: const Text(
              'Şirket uygulamasından ürün adını otomatik almak için '
              'erişilebilirlik servisinin açık olması gerekir. '
              'Ayarları açmak ister misiniz?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ayarları Aç')),
          ],
        ),
      );
      if (go == true) await PriceCheckChannel.openAccessibilitySettings();
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Şirket uygulamasında bu ürünü okutun'),
        duration: Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
      ));
    }
    await PriceCheckChannel.speak('Şirket uygulamasında okutun');
    await PriceCheckChannel.switchToCompanyApp();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _scanner.dispose();
    _expiryCtrl.dispose();
    _qtyCtrl.dispose();
    _caseCtrl.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── VERİTABANI ARAMASI ────────────────────────────────────────────
  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final res = await _dirRepo.search(q);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = res;
      _searching = false;
    });
  }

  Future<void> _pickEntry(BarcodeEntry e) async {
    await _scanner.stop();
    await _select(e.barcode, name: e.productName, stockCode: e.stockCode);
  }

  // ── Ortak seçim: barkod belli olunca formu + akıllı bilgiyi doldur ─
  Future<void> _select(String code,
      {String? name, String? stockCode, DateTime? expiry}) async {
    String? resolved = name;
    String? sc = stockCode;
    if (resolved == null || sc == null) {
      try {
        final entry = await _dirRepo.findEntryByBarcode(code);
        resolved ??= entry?.productName;
        sc ??= entry?.stockCode;
      } catch (_) {}
    }
    if (resolved == null) {
      try {
        resolved = await WarehouseService.instance.resolveName(code);
      } catch (_) {}
    }
    // Urun bu depoda zaten nerede? (akilli konum sorgusu)
    List<ProductLocation> locs = [];
    try {
      locs =
          await WarehouseService.instance.findProduct(widget.warehouseId, code);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _barcode = code;
      _stockCode = sc;
      _expiry = expiry;
      _existingLocs = locs;
      if (resolved != null) _nameCtrl.text = resolved;
      _results = [];
      _searchCtrl.clear();
    });
    // ADI BILINMIYOR + sirket modu acik → sirket uygulamasina gec.
    if ((resolved == null || resolved.trim().isEmpty) && _companyMode) {
      await _goToCompanyApp(code);
    }
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || _barcode != null) return;
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = ScanParser.parse(raw);
    final code = parsed.barcode ?? raw.trim();
    await _scanner.stop();
    if (parsed.expiryDate != null) {
      final d = parsed.expiryDate!;
      _expiryCtrl.text =
          '${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year}';
    }
    await _select(code, expiry: parsed.expiryDate);
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
          '${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year}';
    }
    setState(() => _expiry = d);
  }

  Future<void> _confirm() async {
    if (_barcode == null) return;
    _parseExpiry();
    final qty = (int.tryParse(_qtyCtrl.text.trim()) ?? 1).clamp(1, 9999);
    final name =
        _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim();
    setState(() => _busy = true);

    final itemId = await WarehouseService.instance.addItemToPallet(
      palletId: widget.palletId,
      barcode: _barcode!,
      quantity: qty,
      productName: name,
    );

    // SKT girilmisse SKT listesine KALICI BAGLA ekle: kayit bu palet
    // kalemine baglanir (location_type='pallet'); palet tasinsa da bag
    // gecerli kalir, kalem baska palete TAM tasinirsa ref guncellenir.
    if (_expiry != null) {
      final db = await DatabaseService.instance.database;
      await db.insert('products', {
        'name': name ?? _barcode!,
        'barcode': _barcode!,
        'expiry_date': _expiry!.millisecondsSinceEpoch,
        'quantity': qty,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'disposal_status': 'active',
        'location_type': 'pallet',
        'location_ref': itemId,
      });
    }

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _added++;
      _barcode = null;
      _stockCode = null;
      _expiry = null;
      _existingLocs = [];
      _expiryCtrl.clear();
      _qtyCtrl.text = '1';
      _caseCtrl.clear();
      _nameCtrl.clear();
      _busy = false;
    });
    if (_mode == 0) await _scanner.start();
  }

  void _reset() async {
    setState(() {
      _barcode = null;
      _stockCode = null;
      _expiry = null;
      _existingLocs = [];
      _expiryCtrl.clear();
      _nameCtrl.clear();
    });
    if (_mode == 0) await _scanner.start();
  }

  // ── UI ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // ── HERO BAŞLIK ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(8, topPad + 8, 12, 12),
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
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_added > 0),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.black),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ürün Ekle',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black)),
                          Text(widget.palletCode,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87)),
                        ],
                      ),
                    ),
                    if (_added > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius:
                              BorderRadius.circular(AppTheme.rPill),
                        ),
                        child: Text('$_added eklendi',
                            style: const TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                  ],
                ),
                if (_barcode == null) ...[
                  const SizedBox(height: 6),
                  // TARA | ARA segment secici.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Row(
                        children: [
                          _modeItem(0, Icons.qr_code_scanner_rounded, 'Tara'),
                          _modeItem(1, Icons.manage_search_rounded,
                              'Veritabanında Ara'),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── GÖVDE ───────────────────────────────────────────────
          Expanded(
            child: _barcode == null
                ? (_mode == 0 ? _scanBody() : _searchBody(kb))
                : _formBody(kb, bottomPad),
          ),
        ],
      ),
    );
  }

  Widget _modeItem(int i, IconData icon, String label) {
    final sel = _mode == i;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          if (_mode == i) return;
          setState(() => _mode = i);
          if (i == 0) {
            await _scanner.start();
          } else {
            await _scanner.stop();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: sel ? Colors.black : Colors.black54),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? Colors.black : Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  // ── MOD 1: KAMERA ─────────────────────────────────────────────────
  Widget _scanBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rLg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: _scanner, onDetect: _onDetect),
                  // Nisan cercevesi.
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 230,
                        height: 140,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppTheme.accent, width: 2.5),
                          borderRadius: BorderRadius.circular(AppTheme.rMd),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Barkodu çerçeveye hizala',
              style:
                  TextStyle(fontSize: 12.5, color: AppTheme.textTertiary)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _mode = 1),
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: const Text('Kamera yerine veritabanında ara'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  // ── MOD 2: VERİTABANI ARAMA ───────────────────────────────────────
  Widget _searchBody(double kb) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, kb > 0 ? kb + 8 : 16),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _runSearch,
            decoration: InputDecoration(
              labelText: 'Ürün adı, barkod veya stok kodu',
              prefixIcon: const Icon(Icons.manage_search_rounded),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _results = []);
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.storage_rounded,
                                size: 44,
                                color:
                                    AppTheme.textTertiary.withOpacity(0.5)),
                            const SizedBox(height: 10),
                            Text(
                              _searchCtrl.text.trim().length < 2
                                  ? 'Dizinde aramak için en az 2 harf yazın'
                                  : 'Eşleşme yok — barkodu tarayarak da\nekleyebilirsiniz',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textTertiary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final e = _results[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.rMd),
                              onTap: () => _pickEntry(e),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: AppTheme.card(),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accent
                                            .withOpacity(0.14),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                          Icons.qr_code_2_rounded,
                                          size: 18,
                                          color: AppTheme.accent),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(e.productName,
                                              maxLines: 2,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                          const SizedBox(height: 2),
                                          Text(
                                            e.stockCode != null
                                                ? '${e.barcode} · Stok: ${e.stockCode}'
                                                : e.barcode,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'monospace',
                                                color:
                                                    AppTheme.textTertiary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.add_circle_rounded,
                                        color: AppTheme.accent),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ── FORM: ürün seçildi ────────────────────────────────────────────
  Widget _formBody(double kb, double bottomPad) {
    final pkg = parseProductPackaging(_nameCtrl.text);
    final onThisPallet = _existingLocs
        .where((l) => l.pallet.id == widget.palletId)
        .toList();
    final elsewhere = _existingLocs
        .where((l) => l.pallet.id != widget.palletId)
        .toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, (kb > 0 ? kb : bottomPad) + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barkod + stok kodu karti.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: AppTheme.card(accentColor: AppTheme.accent),
            child: Row(children: [
              const Icon(Icons.qr_code_2_rounded,
                  color: AppTheme.accent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_barcode!,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    if (_stockCode != null)
                      Text('Stok kodu: $_stockCode',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30)),
                onPressed: _reset,
                child:
                    const Text('Değiştir', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          // ── AKILLI KONUM: urun depoda zaten nerede? ──
          if (onThisPallet.isNotEmpty || elsewhere.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border:
                    Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.travel_explore_rounded,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      const Text('Bu ürün depoda zaten var',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final l in onThisPallet)
                        _locChip(
                            'Bu palet · ${l.item.quantity} adet '
                            '(miktar birleşecek)',
                            AppTheme.statusSafe),
                      for (final l in elsewhere)
                        _locChip(
                            '${l.pallet.code}'
                            '${l.shelf != null ? ' · S${l.shelf!.columnNo}·R${l.shelf!.shelfNo}' : ' · Bekleme'}'
                            ' · ${l.item.quantity} adet',
                            AppTheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Urun adi.
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Ürün adı',
              prefixIcon: Icon(Icons.label_outline_rounded),
              isDense: true,
            ),
          ),
          // AD BOS: sirket uygulamasindan cek (fiyat kontrol akisiyla ayni).
          if (_nameCtrl.text.trim().isEmpty && _barcode != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _goToCompanyApp(_barcode!),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Şirkette Okut — ürün adını çek',
                      style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.amber,
                      side: BorderSide(
                          color: AppTheme.amber.withOpacity(0.5))),
                ),
              ),
            ),
          if (pkg.hasAny)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (pkg.piecesPerCase != null)
                    _pkgChip('1 koli = ${pkg.piecesPerCase} adet',
                        Icons.inventory_2_outlined),
                  if (pkg.palletCaseCapacity != null)
                    _pkgChip('Palet max ${pkg.palletCaseCapacity} koli',
                        Icons.view_in_ar_rounded),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // SKT - klavye + OCR.
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
                    labelText: 'SKT (gg.aa.yyyy) — opsiyonel',
                    prefixIcon: Icon(Icons.event_rounded,
                        color:
                            _expiry != null ? AppTheme.statusSafe : null),
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
                message: 'OCR ile tara',
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
          // Adet / koli girisi.
          if (pkg.piecesPerCase == null || pkg.piecesPerCase! <= 0)
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Adet',
                prefixIcon: Icon(Icons.inventory_2_outlined),
                isDense: true,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _caseCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final cases = int.tryParse(v.trim());
                      if (cases != null) {
                        _qtyCtrl.text =
                            (cases * pkg.piecesPerCase!).toString();
                      }
                      setState(() {});
                    },
                    decoration: const InputDecoration(
                      labelText: 'Koli',
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
                    onChanged: (_) => setState(() => _caseCtrl.clear()),
                    decoration: const InputDecoration(
                      labelText: 'Adet',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.add_rounded),
            label: Text(
                _expiry != null ? 'Palete Ekle + SKT Kaydet' : 'Palete Ekle',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context, _added > 0),
            child: Text(_added > 0 ? 'Bitir ($_added eklendi)' : 'Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _locChip(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      );

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
class _TransferScreen extends StatefulWidget {
  final int currentWarehouseId;
  final int? currentShelfId;
  final List<Warehouse> allWarehouses;
  final String palletCode;
  const _TransferScreen({
    required this.currentWarehouseId,
    required this.currentShelfId,
    required this.allWarehouses,
    required this.palletCode,
  });

  @override
  State<_TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<_TransferScreen> {
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
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── HERO ─ tam sayfa "fragment" basligi.
          Container(
            padding: EdgeInsets.fromLTRB(8, topPad + 8, 16, 14),
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
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.black),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Paleti Taşı',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.black)),
                      Text('${widget.palletCode} · hedef depo ve rafı seçin',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

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
                  padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.of(context).padding.bottom + 12),
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
          ),
        ],
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
