import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/fifo_analyzer_service.dart';
import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/location_reveal_prefs.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/services/shelf_restock_service.dart';
import '../../core/services/teshir_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/location_reveal.dart';
import '../widgets/ui_kit.dart';
import '../widgets/warehouse_reveal.dart';
import 'add_product_screen.dart';
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
  // FIFO/FEFO ihlali (bu barkod icin) — varsa uyari karti gosterilir.
  FifoFinding? _fifo;

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
    // 4) FIFO/FEFO ihlali (bu barkod palet<->reyon tarih karsilastirmasi)
    try {
      final findings = await FifoAnalyzerService.instance.analyze();
      FifoFinding? mine;
      for (final f in findings) {
        if (f.barcode == _entry.barcode) {
          mine = f;
          break;
        }
      }
      if (mounted) setState(() => _fifo = mine);
    } catch (_) {}
  }

  // ── HIZLI ISLEMLER (yeni ozellikler) ───────────────────────────────
  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
      backgroundColor: color,
    ));
  }

  /// Etiket basim kuyruguna ekle.
  Future<void> _addToLabelQueue() async {
    try {
      await LabelPendingQueueService.instance.push(
        barcode: _entry.barcode,
        productName: _entry.productName,
        stockCode: _entry.stockCode,
        groupKey: 'barkod_detay',
        source: 'manual',
      );
      _toast('Etiket basım kuyruğuna eklendi', color: AppTheme.statusSuccess);
    } catch (e) {
      _toast('Eklenemedi: $e');
    }
  }

  /// Teshir listesine ekle.
  Future<void> _addToTeshir() async {
    try {
      await TeshirService.instance
          .add(_entry.barcode, productName: _entry.productName);
      _toast('Teşhir listesine eklendi', color: AppTheme.statusSuccess);
    } catch (e) {
      _toast('Eklenemedi: $e');
    }
  }

  /// Reyona acilacaklar listesine ekle.
  Future<void> _addToRestock() async {
    try {
      await ShelfRestockService.instance
          .add(_entry.barcode, productName: _entry.productName);
      _toast('Reyona açılacaklara eklendi', color: AppTheme.statusSuccess);
    } catch (e) {
      _toast('Eklenemedi: $e');
    }
  }

  /// SKT takibine urun ekle (form ekranini barkod+ad ile ac).
  Future<void> _addSkt() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductFormScreen(
        prefillBarcode: _entry.barcode,
        prefillName: _entry.productName,
      ),
    ));
    // Donunce SKT/konum bilgisini tazele.
    _loadContext();
  }

  /// value'ye uygun bir 1D barkod tipi sec (yoksa null -> cizilemez).
  Barcode? _pick1DBarcode(String v0) {
    final v = v0.trim();
    if (!RegExp(r'^\d+$').hasMatch(v)) return null;
    switch (v.length) {
      case 13:
        return Barcode.ean13();
      case 12:
        return Barcode.upcA();
      case 8:
        return Barcode.ean8();
      default:
        return Barcode.code128();
    }
  }

  Color _sevColor(FifoSeverity s) {
    switch (s) {
      case FifoSeverity.high:
        return AppTheme.statusExpired;
      case FifoSeverity.medium:
        return AppTheme.statusCritical;
      case FifoSeverity.low:
        return AppTheme.statusWarning;
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBarForColor(AppTheme.background),
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _posterHeader(),
                _bentoBody(),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomBar(),
        ),
      ),
    );
  }

  /// POSTER BASLIK — kavisli, yuzen fotograf karti (dokun: tam ekran).
  Widget _posterHeader() {
    final hasImage = _localImagePath != null || _imageUrl != null;
    void openZoom() => openImageZoom(context,
        filePath: _localImagePath,
        networkUrl: _localImagePath == null ? _imageUrl : null,
        heroTag: 'bc_img',
        title: _entry.productName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 236,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTap: hasImage ? openZoom : null,
                child: Hero(
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
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x55000000),
                      Colors.transparent,
                      Color(0xE6000000),
                    ],
                    stops: [0.0, 0.42, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: _circleBtn(Icons.arrow_back_rounded,
                    () => Navigator.of(context).pop(_changed)),
              ),
              if (hasImage)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _circleBtn(Icons.fullscreen_rounded, openZoom),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Text(
                  _entry.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 10)]),
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

  Widget _circleBtn(IconData icon, VoidCallback onTap) => Material(
        color: Colors.black.withOpacity(0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );

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

  Widget _bentoBody() {
    final hasAnyLoc = _shelfHit != null || _palletLocs.isNotEmpty;
    final sktQty = _sktProducts.fold<int>(0, (t, p) => t + p.quantity);
    final palletQty = _palletLocs.fold<int>(0, (t, l) => t + l.quantity);
    final totalQty = sktQty + palletQty;
    final locCount = (_shelfHit != null ? 1 : 0) + _palletLocs.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── BENTO UST SATIR: buyuk SKT hero + iki mini kutu ──
          SizedBox(
            height: 190,
            child: Row(
              children: [
                Expanded(flex: 11, child: _sktHeroTile()),
                const SizedBox(width: 12),
                Expanded(
                  flex: 9,
                  child: Column(
                    children: [
                      Expanded(
                          child: _miniTile(Icons.inventory_2_rounded,
                              '$totalQty', 'Toplam Adet', AppTheme.primary)),
                      const SizedBox(height: 12),
                      Expanded(
                          child: _miniTile(Icons.place_rounded, '$locCount',
                              'Konum', AppTheme.statusWarning)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── FIFO/FEFO uyarisi ──
          if (_fifo != null) ...[
            const SizedBox(height: 12),
            _fifoCard(_fifo!),
          ],
          // ── Satir ici taranabilir barkod (yeni) ──
          const SizedBox(height: 12),
          _inlineBarcodeCard(),
          // Stok kodu (varsa).
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
          // ── Tum SKT partileri (yeni: hepsi, FEFO sirali) ──
          if (_sktProducts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _batchesCard(),
          ],
          // ── Reyon konumu — dokun: canlandirma ──
          if (_shelfHit != null) ...[
            const SizedBox(height: 12),
            _shelfCard(_shelfHit!),
          ],
          // ── Depo palet konumlari — dokun: canlandirma ──
          for (final loc in _palletLocs) ...[
            const SizedBox(height: 12),
            _palletCard(loc),
          ],
          if (!hasAnyLoc && _sktProducts.isEmpty) ...[
            const SizedBox(height: 12),
            _stateCard(Icons.location_off_rounded,
                'Bu ürün reyon diziliminde veya depoda kayıtlı değil.'),
          ],
          if (_category != null && _category!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
                icon: Icons.category_rounded,
                label: 'Kategori',
                value: _category!),
          ],
          if (_quantity != null && _quantity!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoCard(
                icon: Icons.straighten_rounded,
                label: 'Miktar / Ağırlık',
                value: _quantity!),
          ],
          // ── Hizli islemler (yeni) ──
          const SizedBox(height: 18),
          _quickActions(),
          if (!_loadingWeb &&
              _imageUrl == null &&
              _category == null &&
              _quantity == null) ...[
            const SizedBox(height: 12),
            _stateCard(Icons.info_outline_rounded,
                'Bu barkod için internette ek bilgi/görsel bulunamadı.'),
          ],
        ],
      ),
    );
  }

  /// Kucuk durum karti (bos konum / internet bilgisi yok).
  Widget _stateCard(IconData icon, String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textTertiary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
          ],
        ),
      );

  /// BENTO: buyuk SKT durum kutusu (renkli gradyan). SKT yoksa "ekle" kutusu.
  Widget _sktHeroTile() {
    if (_sktProducts.isEmpty) {
      return Material(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _addSkt,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_busy_rounded,
                    color: AppTheme.textTertiary, size: 30),
                const Spacer(),
                Text('SKT kaydı yok',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.add_circle_rounded,
                        size: 18, color: AppTheme.primary),
                    const SizedBox(width: 5),
                    Text('SKT ekle',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    final sorted = [..._sktProducts]
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    final nearest = sorted.first;
    final days = nearest.expiryDate.difference(DateTime.now()).inDays;
    final c = days < 0
        ? AppTheme.statusExpired
        : days <= 7
            ? AppTheme.statusCritical
            : days <= 30
                ? AppTheme.statusWarning
                : AppTheme.statusSafe;
    final totalQty = _sktProducts.fold<int>(0, (t, p) => t + p.quantity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, c.withOpacity(0.72)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: c.withOpacity(0.40),
              blurRadius: 18,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 6),
              Text('Son Kullanma',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const Spacer(),
          Text(days < 0 ? '${-days}' : '$days',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  height: 1.0)),
          Text(
              days < 0
                  ? 'gün geçti'
                  : days == 0
                      ? 'bugün doluyor'
                      : 'gün kaldı',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${_fmtDate(nearest.expiryDate)} · $totalQty adet',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 11.5)),
        ],
      ),
    );
  }

  /// BENTO: kucuk kare kutu (sayi + etiket).
  Widget _miniTile(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: color)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  /// FIFO/FEFO uyari karti — palet(arka) stok reyondan erken tarihliyse.
  Widget _fifoCard(FifoFinding f) {
    final c = _sevColor(f.severity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(accentColor: c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: c.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.swap_vert_rounded, color: c, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FIFO/FEFO Uyarısı · ${f.severity.label} öncelik',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: c)),
                    const SizedBox(height: 2),
                    Text(
                        'Paletteki stok reyondan ${f.gapDays} gün DAHA ERKEN.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _fifoRow('Reyon (ön)', _fmtDate(f.shelfExpiry), f.shelfLabel,
              AppTheme.primary),
          const SizedBox(height: 6),
          _fifoRow('Palet (arka)', _fmtDate(f.palletExpiry), f.palletLabel, c),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: c.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: c, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Öneri: paletteki erken tarihli stoğu öne (reyona) al; '
                      'yerlerini değiştir.',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fifoRow(String where, String date, String label, Color c) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        SizedBox(
            width: 92,
            child: Text(where,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary))),
        Text(date,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style:
                    TextStyle(fontSize: 11.5, color: AppTheme.textTertiary))),
      ],
    );
  }

  /// SATIR ICI TARANABILIR BARKOD + deger. Dokun: kopyala, uzun bas: buyut.
  Widget _inlineBarcodeCard() {
    final bc = _pick1DBarcode(_entry.barcode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        onTap: () => _copyValue('Barkod', _entry.barcode),
        onLongPress: () => _showCodeSheet('Barkod', _entry.barcode, true),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.qr_code_2_rounded,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Barkod',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary)),
                        const SizedBox(height: 2),
                        Text(_entry.barcode,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  Icon(Icons.copy_rounded,
                      size: 16, color: AppTheme.textTertiary),
                ],
              ),
              if (bc != null) ...[
                const SizedBox(height: 12),
                // Beyaz zemin: her temada taranabilir kalsin.
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppTheme.rMd)),
                  child: BarcodeWidget(
                    barcode: bc,
                    data: _entry.barcode.trim(),
                    drawText: false,
                    height: 64,
                    color: Colors.black,
                    errorBuilder: (context, error, child) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Dokun: kopyala · Basılı tut: büyüt / QR',
                    style:
                        TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// TUM SKT PARTILERI — FEFO sirali (en yakin once).
  Widget _batchesCard() {
    final sorted = [..._sktProducts]
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_note_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text('SKT Partileri (${sorted.length})',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          for (int i = 0; i < sorted.length; i++)
            _batchRow(sorted[i], i == sorted.length - 1),
        ],
      ),
    );
  }

  Widget _batchRow(Product p, bool last) {
    final days = p.expiryDate.difference(DateTime.now()).inDays;
    final c = days < 0
        ? AppTheme.statusExpired
        : days <= 7
            ? AppTheme.statusCritical
            : days <= 30
                ? AppTheme.statusWarning
                : AppTheme.statusSafe;
    final left = days < 0
        ? '${-days} gün geçti'
        : days == 0
            ? 'Bugün'
            : '$days gün';
    return Padding(
      padding: EdgeInsets.only(top: 10, bottom: last ? 0 : 0),
      child: Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtDate(p.expiryDate),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                if (p.location != null && p.location!.trim().isNotEmpty)
                  Text(p.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${p.quantity} adet',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: c.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999)),
            child: Text(left,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ),
        ],
      ),
    );
  }

  /// HIZLI ISLEMLER — Etiket Bas / Teshir / Reyona Ac / SKT Ekle.
  Widget _quickActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Text('Hızlı İşlemler',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _actionTile(Icons.local_offer_rounded, 'Etiket Bas',
                      AppTheme.primary, _addToLabelQueue)),
              const SizedBox(width: 8),
              Expanded(
                  child: _actionTile(Icons.storefront_rounded, 'Teşhir',
                      AppTheme.accent, _addToTeshir)),
              const SizedBox(width: 8),
              Expanded(
                  child: _actionTile(Icons.shelves, 'Reyona Aç',
                      AppTheme.statusWarning, _addToRestock)),
              const SizedBox(width: 8),
              Expanded(
                  child: _actionTile(Icons.event_available_rounded, 'SKT Ekle',
                      AppTheme.statusSafe, _addSkt)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionTile(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.1)),
            ],
          ),
        ),
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
                errorBuilder: (context, error, child) => Text(
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
