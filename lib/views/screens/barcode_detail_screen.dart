import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/location_reveal_prefs.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/location_reveal.dart';
import '../widgets/ui_kit.dart';
import '../widgets/warehouse_reveal.dart';
import 'image_zoom_screen.dart';
import 'web_search_screen.dart';

/// Barkod liste oge detay sayfasi.
/// - Urun adi VERITABANINDAN (dizinden) gelir.
/// - Gorsel + ek bilgi (kategori/miktar) Open Food Facts'ten cekilir.
/// - Duzenle / Sil aksiyonlari altta sabit.
class BarcodeDetailScreen extends ConsumerStatefulWidget {
  final BarcodeEntry entry;
  const BarcodeDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<BarcodeDetailScreen> createState() =>
      _BarcodeDetailScreenState();
}

class _BarcodeDetailScreenState extends ConsumerState<BarcodeDetailScreen> {
  late BarcodeEntry _entry;
  bool _loadingWeb = true;
  String? _imageUrl;
  // Telefondaki (yerel) foto yolu — zoom acilirken oncelikli kullanilir.
  String? _localImagePath;
  String? _category;
  String? _quantity;
  bool _changed = false; // geri donerken listeyi yenilemek icin

  // ── ZENGIN BAGLAM: SKT + reyon + depo ────────────────────────────
  // Bu barkodla kayitli aktif SKT urunleri (en yakin tarih once).
  List<Product> _sktProducts = const [];
  // Reyon dizilimindeki yeri (varsa) — dokununca canlandirma oynar.
  ShelfLocationHit? _shelfHit;
  // Depodaki palet konumlari — dokununca depo canlandirmasi oynar.
  List<_BcPalletLoc> _palletLocs = const [];

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _fetchWeb();
    _loadLocalImage();
    _loadContext();
  }

  /// SKT kayitlari + reyon konumu + depo palet konumlarini yukle.
  Future<void> _loadContext() async {
    // 1) SKT
    try {
      final list = await ref
          .read(productRepositoryProvider)
          .findActiveListByBarcode(_entry.barcode);
      if (mounted) setState(() => _sktProducts = list);
    } catch (_) {}
    // 2) Reyon
    try {
      final hit =
          await ShelfLayoutService.instance.locateBarcode(_entry.barcode);
      if (mounted) setState(() => _shelfHit = hit);
    } catch (_) {}
    // 3) Depo paletleri (tum depolarda ara; canlandirma icin izgara bilgisi)
    try {
      final out = <_BcPalletLoc>[];
      final whs = await WarehouseService.instance.getWarehouses();
      for (final w in whs) {
        final locs =
            await WarehouseService.instance.findProduct(w.id!, _entry.barcode);
        if (locs.isEmpty) continue;
        int gc = 1, gr = 1;
        final colRowCounts = <int, int>{};
        try {
          final shelves = await WarehouseService.instance.getShelves(w.id!);
          for (final sh in shelves) {
            if (sh.columnNo > gc) gc = sh.columnNo;
            if (sh.shelfNo > gr) gr = sh.shelfNo;
            final cur = colRowCounts[sh.columnNo] ?? 0;
            if (sh.shelfNo > cur) colRowCounts[sh.columnNo] = sh.shelfNo;
          }
        } catch (_) {}
        for (final l in locs) {
          out.add(_BcPalletLoc(
            warehouseName: w.name,
            palletCode: l.pallet.code,
            shelfLabel: l.shelf != null
                ? 'Sütun ${l.shelf!.columnNo} · Raf ${l.shelf!.shelfNo}'
                : 'Zemin',
            quantity: l.item.quantity,
            colNo: l.shelf?.columnNo,
            shelfNo: l.shelf?.shelfNo,
            gridCols: gc,
            gridRows: gr,
            colShelfCounts: colRowCounts,
            allWarehouses: whs.map((x) => x.name).toList(),
            warehouseIndex: whs.indexOf(w),
            palletPhotoPath: l.pallet.imagePath,
          ));
        }
      }
      if (mounted) setState(() => _palletLocs = out);
    } catch (_) {}
  }

  /// Reyon canlandirmasini oynat (kullanici dokununca).
  void _playShelfReveal() {
    final hit = _shelfHit;
    if (hit == null) return;
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
      productName: hit.productName ?? _entry.productName,
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

  /// Depo canlandirmasini oynat (kullanici dokununca).
  void _playWarehouseReveal(_BcPalletLoc loc) {
    showWarehouseFlythrough(
      context,
      warehouseName: loc.warehouseName,
      cols: loc.gridCols,
      rows: loc.gridRows,
      colShelfCounts: loc.colShelfCounts,
      targetCol: loc.colNo,
      targetRow: loc.shelfNo,
      palletCode: loc.palletCode,
      shelfLabel: loc.shelfLabel,
      quantity: loc.quantity,
      productName: _entry.productName,
      localPhotos: [
        if (_localImagePath != null) _localImagePath!,
      ],
      palletPhotoPath: loc.palletPhotoPath,
      allWarehouses: loc.allWarehouses,
      targetWarehouseIndex: loc.warehouseIndex,
    );
  }

  Future<void> _loadLocalImage() async {
    try {
      final p = await ref
          .read(barcodeDirectoryDataSourceProvider)
          .getLocalImage(_entry.barcode);
      if (mounted && p != null && p.isNotEmpty && File(p).existsSync()) {
        setState(() => _localImagePath = p);
      }
    } catch (_) {}
  }

  /// OFF'tan gorsel + ek bilgi. Ad'a dokunmaz (o veritabanindan).
  Future<void> _fetchWeb() async {
    try {
      final r =
          await BarcodeLookupService.instance.lookupDetailed(_entry.barcode);
      if (!mounted) return;
      setState(() {
        _imageUrl = r.imageUrl;
        _category = r.category;
        _quantity = r.quantity;
        _loadingWeb = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingWeb = false);
    }
  }

  Future<void> _edit() async {
    final nameCtrl = TextEditingController(text: _entry.productName);
    final stockCtrl =
        TextEditingController(text: _entry.stockCode ?? '');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ürün adı',
                hintText: 'Ürün adı',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: stockCtrl,
              decoration: const InputDecoration(
                labelText: 'Stok kodu (opsiyonel)',
                hintText: 'Stok kodu',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                    'name': nameCtrl.text.trim(),
                    'stock': stockCtrl.text.trim(),
                  }),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (result == null) return;
    final newName = result['name'] ?? '';
    if (newName.isEmpty) return;
    final newStock = result['stock'] ?? '';

    await ref.read(barcodeDirectoryRepositoryProvider).importAll([
      BarcodeEntry(
        barcode: _entry.barcode,
        productName: newName,
        // Bos birakilirsa eski stok kodu importAll tarafindan korunur.
        stockCode: newStock.isEmpty ? null : newStock,
        importedAt: DateTime.now(),
        // Elle duzenleme: mevcut kaydin kaynagini KORU ki (esit oncelik)
        // degisiklik her zaman uygulansin. Boylece bir Excel kaydini elle
        // duzeltince "excel" onceligi korunur ama ad/stok yine guncellenir.
        source: _entry.source == BarcodeSource.unknown
            ? BarcodeSource.manual
            : _entry.source,
      ),
    ]);

    // id artik importAll merge davranisiyla degismez; yine de guncel kaydi cek.
    final fresh = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .findEntryByBarcode(_entry.barcode);

    if (mounted) {
      setState(() {
        _entry = fresh ??
            BarcodeEntry(
              barcode: _entry.barcode,
              productName: newName,
              stockCode: newStock.isEmpty ? _entry.stockCode : newStock,
              importedAt: DateTime.now(),
            );
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellendi')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sil'),
        content: Text('"${_entry.productName}" listeden silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true && _entry.id != null) {
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .deleteById(_entry.id!);
      if (mounted) Navigator.of(context).pop(true); // silindi -> yenile
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomScrollView(
          slivers: [
            _buildHeader(),
            SliverToBoxAdapter(child: _buildBody()),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildHeader() {
    final hasImage = _localImagePath != null || _imageUrl != null;
    return SliverAppBar(
      expandedHeight: hasImage ? 340 : 220,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(_changed),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        // ÜST KISIM FOTO: fotograf banner'in tamamini kaplar; dokununca
        // tam ekran acilir. Yerel foto internet gorselinden onceliklidir.
        background: GestureDetector(
          onTap: (!hasImage)
              ? null
              : () => openImageZoom(context,
                  filePath: _localImagePath,
                  networkUrl: _localImagePath == null ? _imageUrl : null,
                  heroTag: 'bc_img',
                  title: _entry.productName),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'bc_img',
                child: _localImagePath != null
                    ? Image.file(File(_localImagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _heroBg())
                    : (_imageUrl != null
                        ? SmartProductImage(
                            networkUrl: _imageUrl,
                            barcode: _entry.barcode,
                            fit: BoxFit.cover,
                            placeholder: _heroBgIcon,
                          )
                        : _heroBg()),
              ),
              // Okunabilirlik perdesi (alt).
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
              if (hasImage)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 6,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.fullscreen_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              // Urun adi — banner altinda.
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Text(
                  _entry.productName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ]),
                ),
              ),
              if (_loadingWeb && !hasImage)
                const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroBg() => Container(
        decoration: const BoxDecoration(gradient: AppTheme.bannerGradient),
        child: const Center(
          child: Icon(Icons.inventory_2_rounded,
              color: Colors.white, size: 56),
        ),
      );

  Widget _heroBgIcon() => const Center(
        child: Icon(Icons.inventory_2_rounded,
            color: Colors.white, size: 56),
      );

  Widget _ph() => const Icon(Icons.inventory_2_rounded,
      color: Colors.white, size: 52);

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barkod karti — tikla: kopyala, uzun bas: barkod/QR goster.
          _infoCard(
            icon: Icons.qr_code_rounded,
            label: 'Barkod',
            value: _entry.barcode,
            monospace: true,
            copyable: true,
            showCode: true,
            isBarcode: true,
          ),
          // ── TANIMLI SKT (varsa) ──
          if (_sktProducts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sktCard(),
          ],
          // ── REYON KONUMU (varsa) — dokun: canlandirma ──
          if (_shelfHit != null) ...[
            const SizedBox(height: 12),
            _shelfCard(_shelfHit!),
          ],
          // ── DEPO KONUMLARI (varsa) — dokun: depo canlandirmasi ──
          for (final loc in _palletLocs) ...[
            const SizedBox(height: 12),
            _palletCard(loc),
          ],
          if (_shelfHit == null && _palletLocs.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.card(),
              child: Row(
                children: [
                  Icon(Icons.location_off_rounded,
                      color: AppTheme.textTertiary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu ürün reyon diziliminde veya depoda kayıtlı değil.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Stok kodu karti (Excel'den geldiyse).
          if (_entry.stockCode != null && _entry.stockCode!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.tag_rounded,
              label: 'Stok Kodu',
              value: _entry.stockCode!,
              monospace: true,
              copyable: true,
              showCode: true,
              isBarcode: false,
            ),
          ],
          if (_category != null && _category!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.category_rounded,
              label: 'Kategori',
              value: _category!,
            ),
          ],
          if (_quantity != null && _quantity!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.straighten_rounded,
              label: 'Miktar / Ağırlık',
              value: _quantity!,
            ),
          ],
          if (!_loadingWeb &&
              _imageUrl == null &&
              _category == null &&
              _quantity == null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.card(),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.textTertiary, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu barkod için internette ek bilgi/görsel bulunamadı.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// TANIMLI SKT karti: en yakin tarih + kalan gun + toplam kayit/adet.
  Widget _sktCard() {
    final nearest = _sktProducts.first;
    final days = nearest.expiryDate
        .difference(DateTime.now())
        .inDays;
    final Color c = days < 0
        ? AppTheme.statusExpired
        : days <= 7
            ? AppTheme.statusCritical
            : days <= 30
                ? AppTheme.statusWarning
                : AppTheme.statusSafe;
    final totalQty =
        _sktProducts.fold<int>(0, (t, p) => t + p.quantity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(accentColor: c),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_rounded, color: c, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tanımlı SKT',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textTertiary)),
                const SizedBox(height: 2),
                Text(
                  '${nearest.expiryDate.day.toString().padLeft(2, '0')}.'
                  '${nearest.expiryDate.month.toString().padLeft(2, '0')}.'
                  '${nearest.expiryDate.year}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: c),
                ),
                const SizedBox(height: 2),
                Text(
                  days < 0
                      ? '${-days} gün geçti · $totalQty adet'
                      : '$days gün kaldı · $totalQty adet'
                          '${_sktProducts.length > 1 ? ' · ${_sktProducts.length} kayıt' : ''}',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// REYON konum karti — dokununca reyon canlandirmasi oynar.
  Widget _shelfCard(ShelfLocationHit hit) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: _playShelfReveal,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(accentColor: AppTheme.primary),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.shelves,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reyonda',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textTertiary)),
                  const SizedBox(height: 2),
                  Text(hit.unitName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  Text('Sütun ${hit.section} · Raf ${hit.row}',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Column(
              children: const [
                Icon(Icons.play_circle_fill_rounded,
                    color: AppTheme.primary, size: 28),
                SizedBox(height: 2),
                Text('Canlandır',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// DEPO palet karti — dokununca depo canlandirmasi oynar.
  Widget _palletCard(_BcPalletLoc loc) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => _playWarehouseReveal(loc),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(accentColor: AppTheme.accent),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warehouse_rounded,
                  color: AppTheme.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Depoda',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textTertiary)),
                  const SizedBox(height: 2),
                  Text('${loc.warehouseName} · ${loc.palletCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  Text('${loc.shelfLabel} · ${loc.quantity} adet',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Column(
              children: const [
                Icon(Icons.play_circle_fill_rounded,
                    color: AppTheme.accent, size: 28),
                SizedBox(height: 2),
                Text('Canlandır',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    bool monospace = false,
    Widget? trailing,
    bool copyable = false,
    bool showCode = false,
    bool isBarcode = false,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: monospace ? 'monospace' : null)),
                if (copyable || showCode) ...[
                  const SizedBox(height: 4),
                  Text(
                    showCode
                        ? 'Kopyalamak için dokun • Kod için basılı tut'
                        : 'Kopyalamak için dokun',
                    style: TextStyle(
                        fontSize: 10.5, color: AppTheme.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (copyable)
            Icon(Icons.copy_rounded,
                size: 16, color: AppTheme.textTertiary),
          if (trailing != null) trailing,
        ],
      ),
    );

    if (!copyable && !showCode) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: copyable ? () => _copyValue(label, value) : null,
        onLongPress:
            showCode ? () => _showCodeSheet(label, value, isBarcode) : null,
        child: card,
      ),
    );
  }

  /// Degeri panoya kopyala + kisa bildirim.
  void _copyValue(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label kopyalandı: $value'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Alttan kayan pencerede degerin barkod + QR gorselini gosterir.
  void _showCodeSheet(String label, String value, bool isBarcode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CodeSheet(
        label: label,
        value: value,
        // Barkod yalnizca EAN-13/EAN-8/UPC gibi gecerli sayisal kodlarda
        // cizilebilir; degilse sadece QR gosterilir.
        preferBarcode: isBarcode,
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _edit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzenle',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WebSearchScreen(query: _entry.barcode),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: BorderSide(color: AppTheme.accent.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text("İnternette Ara"),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusExpired,
                    side: const BorderSide(color: AppTheme.statusExpired),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sil'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bir degerin (barkod/stok kodu) barkod + QR gorselini gosteren alt sheet.
/// Gecerli EAN-13/EAN-8/UPC ise 1D barkod cizilir; her durumda QR gosterilir.
class _CodeSheet extends StatelessWidget {
  final String label;
  final String value;
  final bool preferBarcode;

  const _CodeSheet({
    required this.label,
    required this.value,
    this.preferBarcode = false,
  });

  /// value'ye uygun bir 1D barkod tipi sec (yoksa null -> sadece QR).
  Barcode? _pick1DBarcode() {
    final v = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return null; // salt rakam degil
    switch (v.length) {
      case 13:
        return Barcode.ean13();
      case 12:
        return Barcode.upcA();
      case 8:
        return Barcode.ean8();
      default:
        // Diger uzunluklar icin Code128 (rakam+harf destekler).
        return Barcode.code128();
    }
  }

  @override
  Widget build(BuildContext context) {
    final barcode = preferBarcode ? _pick1DBarcode() : null;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace'),
          ),
          const SizedBox(height: 20),

          // 1D Barkod (varsa) — beyaz zemin uzerine, taranabilir olsun.
          if (barcode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
              child: BarcodeWidget(
                barcode: barcode,
                data: value.trim(),
                drawText: true,
                height: 90,
                color: Colors.black,
                errorBuilder: (context, error) => Text(
                  'Barkod oluşturulamadı',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text('— veya —',
                  style: TextStyle(
                      color: AppTheme.textTertiary, fontSize: 12)),
            ),
            const SizedBox(height: 18),
          ],

          // QR kod — her zaman.
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.rMd),
              ),
              child: QrImageView(
                data: value.trim(),
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
                // ignore: deprecated_member_use
                foregroundColor: Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label kopyalandı'),
                  duration: const Duration(milliseconds: 1200),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Kopyala'),
          ),
        ],
      ),
    );
  }
}


/// Barkod detayinda gosterilen depo palet konumu (canlandirma verisiyle).
class _BcPalletLoc {
  final String warehouseName;
  final String palletCode;
  final String shelfLabel;
  final int quantity;
  final int? colNo;
  final int? shelfNo;
  final int gridCols;
  final int gridRows;
  final Map<int, int> colShelfCounts;
  final List<String> allWarehouses;
  final int warehouseIndex;
  final String? palletPhotoPath;
  const _BcPalletLoc({
    required this.warehouseName,
    required this.palletCode,
    required this.shelfLabel,
    required this.quantity,
    this.colNo,
    this.shelfNo,
    required this.gridCols,
    required this.gridRows,
    required this.colShelfCounts,
    required this.allWarehouses,
    required this.warehouseIndex,
    this.palletPhotoPath,
  });
}
