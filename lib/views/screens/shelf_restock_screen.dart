import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/services/feedback_service.dart';
import '../widgets/scan_error_retry.dart';
import '../../core/camera_lifecycle_mixin.dart';

import '../../core/services/database_service.dart';
import '../../core/services/flow_prefs.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/services/shelf_restock_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/repositories/barcode_directory_repository.dart';
import '../widgets/ui_kit.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYONA ACILACAKLAR (v141)
///  Akis: barkod okut (el terminali ODAKLI/klavyesiz ya da kamera) →
///  urun listeye eklenir, depodaki palet konumu gosterilir → "Depodan
///  Cikar" ile FEFO dusum yapilir ve oge tamamlanir. Sabah reyon acma
///  operasyonunun tek ekrani.
/// ════════════════════════════════════════════════════════════════════
class ShelfRestockScreen extends StatefulWidget {
  const ShelfRestockScreen({super.key});
  @override
  State<ShelfRestockScreen> createState() => _ShelfRestockScreenState();
}

class _ShelfRestockScreenState extends State<ShelfRestockScreen> with CameraLifecycleMixin {
  // Kamera yasam dongusu: arka plandan donunce kamera unlem/takilma
  // yasamasin diye durdur/yeniden baslat.
  @override
  List<MobileScannerController> get cameraControllers => [if (_scanner != null) _scanner!];
  List<Map<String, Object?>> _items = [];
  // barkod -> depodaki konumlar (onbellek).
  final Map<String, List<ProductLocation>> _locCache = {};
  bool _busy = false;
  bool _cameraOn = false;

  final TextEditingController _hidCtrl = TextEditingController();
  final FocusNode _hidFocus = FocusNode();
  MobileScannerController? _scanner;
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  // ── SIRKET UYGULAMASI ENTEGRASYONU (fiyat kontrol akisiyla ayni) ──
  // Adi bilinmeyen barkod okutulunca sirket uygulamasina geciyoruz;
  // orada okutunca erisilebilirlik servisi urun adi/stok kodunu okuyup
  // systemPriceStream ile bize gonderiyor. Gelen veri hem listeye hem
  // barkod dizinine yaziliyor (bir daha sorulmaz).
  bool _companyMode = false;
  bool _serviceOn = false;
  StreamSubscription<SystemPriceSnapshot>? _liveSub;
  String? _awaitingBarcode; // sirkette okutulmasi beklenen barkod
  int? _awaitingId; // hangi liste ogesine yazilacak

  @override
  void initState() {
    super.initState();
    _load();
    _initCompanyFlow();
  }

  /// Sirket uygulamasi akisini hazirla: tercih + servis durumu + canli
  /// veri akisi aboneligi.
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
    // Canli sistem verisi: sirket uygulamasinda urun okununca tetiklenir.
    _liveSub = PriceCheckChannel.systemPriceStream.listen(_onSystemData);
  }

  /// Sirket uygulamasindan gelen urun bilgisi — bekleyen ogeye yaz.
  Future<void> _onSystemData(SystemPriceSnapshot sys) async {
    final name = sys.productName?.trim();
    if (name == null || name.isEmpty) return;
    if (_looksLikeStaticFormLabel(name)) return; // ekran basligi, urun degil

    // Hedef: bekledigimiz oge; yoksa sistemin verdigi barkoda ait bekleyen.
    int? targetId = _awaitingId;
    String? targetBarcode = _awaitingBarcode;
    if (targetId == null) {
      final sysBc = sys.barcode?.trim();
      if (sysBc == null || sysBc.isEmpty) return;
      final row = await ShelfRestockService.instance.pendingByBarcode(sysBc);
      if (row == null) return;
      targetId = row['id'] as int;
      targetBarcode = sysBc;
    }
    if (targetBarcode == null) return;

    // 1) Liste ogesine adi yaz.
    await ShelfRestockService.instance.updateName(targetId, name);
    // 2) Barkod dizinine de yaz — bir daha sirkete gitmeye gerek kalmasin.
    try {
      await BarcodeDirectoryDataSource(DatabaseService.instance).importAll([
        BarcodeEntry(
          barcode: targetBarcode,
          productName: name,
          stockCode: sys.stockCode?.trim(),
          importedAt: DateTime.now(),
          source: BarcodeSource.screen,
        )
      ]);
    } catch (_) {}

    _awaitingBarcode = null;
    _awaitingId = null;
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    FeedbackService.instance.play(ScanFeedback.product);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Şirket verisi alındı: $name'),
      duration: const Duration(milliseconds: 1400),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.statusSafe,
    ));
    if (mounted) _hidFocus.requestFocus();
  }

  /// Sirket uygulamasindaki sabit ekran basliklarini urun adi sanmayalim.
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

  /// Sirket uygulamasina gec: [barcode] orada okutulacak.
  Future<void> _goToCompanyApp(int id, String barcode) async {
    _awaitingId = id;
    _awaitingBarcode = barcode;
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

  Future<void> _toggleCompanyMode(bool v) async {
    setState(() => _companyMode = v);
    await FlowPrefs.instance.setAutoFlow(v);
    await PriceCheckChannel.setAutoFlow(v);
    if (v) {
      final on = await PriceCheckChannel.isServiceRunning();
      if (mounted) setState(() => _serviceOn = on);
    }
  }

  @override
  void dispose() {
    _hidCtrl.dispose();
    _hidFocus.dispose();
    _scanner?.dispose();
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ShelfRestockService.instance.list();
    if (!mounted) return;
    setState(() => _items = items);
  }

  /// Barkodun depodaki palet konumlari (tum depolarda) — onbellekli.
  Future<List<ProductLocation>> _locations(String barcode) async {
    final cached = _locCache[barcode];
    if (cached != null) return cached;
    final out = <ProductLocation>[];
    try {
      final whs = await WarehouseService.instance.getWarehouses();
      for (final w in whs) {
        out.addAll(
            await WarehouseService.instance.findProduct(w.id!, barcode));
      }
    } catch (_) {}
    _locCache[barcode] = out;
    return out;
  }

  // ── OKUTMA ──────────────────────────────────────────────────────────
  Future<void> _onHidSubmit(String v) async {
    final t = v.trim();
    _hidCtrl.clear();
    if (t.isNotEmpty) await _addScan(t);
    if (mounted) _hidFocus.requestFocus();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    // Kamera ayni kodu saniyede defalarca gorur; kisa soğuma uygula.
    final now = DateTime.now();
    if (now.difference(_lastScan).inMilliseconds < 1200) return;
    _lastScan = now;
    await _addScan(raw);
  }

  /// Ortak ekleme hatti: barkodu ayikla, adi dizinden bul, listeye ekle.
  Future<void> _addScan(String raw) async {
    final code = ScanParser.parse(raw).barcode ?? raw.trim();
    if (code.isEmpty) return;
    String? name;
    try {
      name = await BarcodeDirectoryRepository(
              BarcodeDirectoryDataSource(DatabaseService.instance))
          .findProductName(code);
    } catch (_) {}
    final id =
        await ShelfRestockService.instance.add(code, productName: name);
    _locCache.remove(code); // konum tazelensin
    HapticFeedback.mediumImpact();
    await _load();
    if (!mounted) return;
    final unknown = name == null || name.trim().isEmpty;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(unknown ? 'Eklendi: $code (ad bilinmiyor)' : 'Eklendi: $name'),
      duration: const Duration(milliseconds: 900),
      behavior: SnackBarBehavior.floating,
    ));
    // ADI BILINMIYOR + sirket modu acik → sirket uygulamasina gec.
    // Orada okutunca ad/stok kodu otomatik gelir (_onSystemData).
    if (unknown && _companyMode) {
      await _goToCompanyApp(id, code);
    }
  }

  // ── DEPODAN CIKAR ───────────────────────────────────────────────────
  Future<void> _pull(Map<String, Object?> item) async {
    if (_busy) return;
    final barcode = item['barcode'] as String;
    final qty = (item['quantity'] as int?) ?? 1;
    setState(() => _busy = true);
    final locs = await _locations(barcode);
    if (!mounted) return;
    setState(() => _busy = false);

    if (locs.isEmpty) {
      // Depoda yok: yine de tamam isaretleme secenegi sun.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Depoda bulunamadı'),
          content: const Text(
              'Bu barkod depo paletlerinde kayıtlı değil. Yine de '
              '"reyona açıldı" olarak işaretlensin mi?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('İşaretle')),
          ],
        ),
      );
      if (ok == true) {
        await ShelfRestockService.instance.markDone(item['id'] as int);
        _load();
      }
      return;
    }

    // Birden fazla paletteyse sec; tek ise direkt onayla.
    ProductLocation? chosen = locs.length == 1 ? locs.first : null;
    chosen ??= await showModalBottomSheet<ProductLocation>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Hangi paletten çıkarılsın?',
                  style: TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
            ),
            for (final l in locs)
              ListTile(
                leading: Icon(Icons.warehouse_rounded,
                    color: AppTheme.accent),
                title: Text(l.pallet.code,
                    style:
                        const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                    '${l.shelf != null ? 'Sütun ${l.shelf!.columnNo} · Raf ${l.shelf!.shelfNo}' : 'Zemin'}'
                    ' · ${l.item.quantity} adet mevcut'),
                onTap: () => Navigator.pop(ctx, l),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final take = qty.clamp(1, chosen.item.quantity);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Depodan Çıkar'),
        content: Text(
            '${item['product_name'] ?? barcode}\n\n'
            '${chosen!.pallet.code} paletinden $take adet çıkarılacak '
            '(mevcut ${chosen.item.quantity}). SKT partileri FEFO '
            'sırasıyla düşülür.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Çıkar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ShelfRestockService.instance.pullFromWarehouse(
        restockId: item['id'] as int,
        palletItemId: chosen.item.id!,
        qty: take,
      );
      _locCache.remove(barcode);
      HapticFeedback.heavyImpact();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _load();
  }

  // ── UI ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final pending = _items.where((i) => i['done'] == 0).toList();
    final done = _items.where((i) => i['done'] == 1).toList();
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _hero(pending.length, done.length),
          if (_cameraOn)
            SizedBox(
              height: 170,
              child: MobileScanner(
                  controller: _scanner ??= MobileScannerController(),
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) =>
                      ScanErrorRetry(controller: _scanner!)),
            ),
          _hidBar(),
          Expanded(
            child: _items.isEmpty
                ? const EmptyState(
                    icon: Icons.playlist_add_rounded,
                    title: 'Liste boş',
                    subtitle:
                        'Reyona açılacak ürünlerin barkodlarını el '
                        'terminaliyle ya da kamerayla okutun; depodan '
                        'çıkarma buradan tek dokunuşla yapılır.',
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(16, 8, 16,
                        MediaQuery.of(context).padding.bottom + 16),
                    children: [
                      for (final it in pending) _card(it, false),
                      if (done.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                          child: Row(
                            children: [
                              Text('TAMAMLANAN (${done.length})',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textTertiary)),
                              const Spacer(),
                              TextButton(
                                onPressed: () async {
                                  await ShelfRestockService.instance
                                      .clearDone();
                                  _load();
                                },
                                child: const Text('Temizle',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                        for (final it in done) _card(it, true),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hero(int pending, int done) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary,
            Color.lerp(AppTheme.primary, AppTheme.accent, 0.6)!,
          ],
        ),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reyona Açılacaklar',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                Text('$pending bekliyor · $done tamam',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          // SIRKET UYGULAMASI MODU: adi bilinmeyen barkodda otomatik gecis.
          IconButton(
            tooltip: _companyMode
                ? 'Şirket uygulaması entegrasyonu AÇIK'
                : 'Şirket uygulaması entegrasyonu kapalı',
            onPressed: () => _toggleCompanyMode(!_companyMode),
            icon: Icon(
                _companyMode
                    ? Icons.sync_alt_rounded
                    : Icons.sync_disabled_rounded,
                color: _companyMode ? Colors.white : Colors.white54),
          ),
          IconButton(
            tooltip: _cameraOn ? 'Kamerayı kapat' : 'Kamerayla okut',
            onPressed: () {
              setState(() => _cameraOn = !_cameraOn);
              if (!_cameraOn) {
                _scanner?.dispose();
                _scanner = null;
              }
            },
            icon: Icon(
                _cameraOn
                    ? Icons.no_photography_rounded
                    : Icons.photo_camera_rounded,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _hidBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.settings_remote_rounded,
                size: 16, color: AppTheme.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _hidCtrl,
                focusNode: _hidFocus,
                autofocus: true, // imlec acilista burada
                keyboardType: TextInputType.none, // klavye ACILMAZ
                textInputAction: TextInputAction.done,
                onSubmitted: _onHidSubmit,
                style: const TextStyle(
                    fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'El terminali: barkodu buraya okutun',
                  hintStyle: TextStyle(
                      fontSize: 12, color: AppTheme.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, Object?> it, bool isDone) {
    final barcode = it['barcode'] as String;
    final name = (it['product_name'] as String?) ?? barcode;
    final qty = (it['quantity'] as int?) ?? 1;
    return Opacity(
      opacity: isDone ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: AppTheme.card(
            accentColor: isDone ? AppTheme.statusSafe : AppTheme.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Adet rozeti — bekleyenlerde dokununca duzenlenir.
                InkWell(
                  onTap: isDone ? null : () => _editQty(it),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (isDone
                              ? AppTheme.statusSafe
                              : AppTheme.primary)
                          .withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$qty',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: isDone
                                ? AppTheme.statusSafe
                                : AppTheme.primary)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(barcode,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
                if (isDone)
                  const Icon(Icons.check_circle_rounded,
                      color: AppTheme.statusSafe, size: 22)
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Listeden çıkar',
                    onPressed: () async {
                      await ShelfRestockService.instance
                          .remove(it['id'] as int);
                      _load();
                    },
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: AppTheme.textTertiary),
                  ),
              ],
            ),
            if (!isDone && name == barcode) ...[
              const SizedBox(height: 8),
              // ADI BILINMIYOR: sirket uygulamasindan cek.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _goToCompanyApp(it['id'] as int, barcode),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Şirkette Okut — ürün adını çek',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.amber,
                      side: BorderSide(
                          color: AppTheme.amber.withOpacity(0.5))),
                ),
              ),
            ],
            if (!isDone) ...[
              const SizedBox(height: 8),
              // Depo konumu (onbellekli) + Depodan Cikar.
              FutureBuilder<List<ProductLocation>>(
                future: _locations(barcode),
                builder: (_, snap) {
                  final locs = snap.data;
                  final label = locs == null
                      ? 'Depo aranıyor…'
                      : locs.isEmpty
                          ? 'Depoda kayıtlı değil'
                          : '${locs.first.pallet.code}'
                              '${locs.first.shelf != null ? ' · S${locs.first.shelf!.columnNo}R${locs.first.shelf!.shelfNo}' : ' · Zemin'}'
                              ' · ${locs.fold<int>(0, (t, l) => t + l.item.quantity)} adet'
                              '${locs.length > 1 ? ' · ${locs.length} palet' : ''}';
                  return Row(
                    children: [
                      Icon(Icons.warehouse_rounded,
                          size: 14,
                          color: (locs?.isEmpty ?? false)
                              ? AppTheme.textTertiary
                              : AppTheme.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: (locs?.isEmpty ?? false)
                                    ? AppTheme.textTertiary
                                    : AppTheme.accent)),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _pull(it),
                        style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12)),
                        child: const Text('Depodan Çıkar',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editQty(Map<String, Object?> it) async {
    final ctrl =
        TextEditingController(text: '${(it['quantity'] as int?) ?? 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adet'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (v != null && v >= 1) {
      await ShelfRestockService.instance.updateQty(it['id'] as int, v);
      _load();
    }
  }
}
