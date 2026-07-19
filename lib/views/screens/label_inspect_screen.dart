import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/location_reveal_prefs.dart';
import '../../core/services/price_change_service.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/services/warehouse_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/location_reveal.dart';
import '../widgets/scan_overlay.dart';
import '../widgets/warehouse_reveal.dart';
import '../../core/utils/scan_parser.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
import 'web_search_screen.dart';

/// Etiket Inceleme: tek etiket okut -> icindeki HER SEYI goster.
/// Fiyat, SKT, basim tarihi, barkod, dizin adi, OFF bilgisi (gorsel,
/// kategori, miktar), web aramasi.
class LabelInspectScreen extends ConsumerStatefulWidget {
  const LabelInspectScreen({super.key});

  @override
  ConsumerState<LabelInspectScreen> createState() =>
      _LabelInspectScreenState();
}

class _LabelInspectScreenState extends ConsumerState<LabelInspectScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  bool _scanning = true;
  bool _busy = false;

  // Okunan etiket verileri
  ScanResult? _parsed;
  String? _localName; // dizin/urunlerden
  BarcodeLookupResult? _off;

  // App bar rengi: bir onceki taranan barkodla karsilastirma.
  // null = ilk tarama (notr); yesil = ayni barkod; kirmizi = farkli barkod.
  String? _lastBarcode;
  Color _appBarColor = AppTheme.primary;
  // Taranan urunun reyon konumu (varsa) — animasyonlu kartla gosterilir.
  _ShelfLocation? _shelfLoc;
  // Ayni urunun DEPO/palet konumlari (reyon bos olsa da depoda olabilir).
  List<_PalletLocation> _palletLocs = const [];
  // Urune ait YEREL fotograflar (Fiyat Kontrol'de cekilmis etiket/kanit
  // fotograflari). OFF'un ag gorseli yoksa/varsa bile once bunlar gosterilir.
  List<String> _localPhotos = const [];

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      await _controller.start();
    }
    if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Kamera izni gerekli. Lutfen uygulama ayarlarindan izin verin.'),
          action: SnackBarAction(
            label: 'Ayarlar',
            onPressed: openAppSettings,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _scanning = false;
    });
    await _controller.stop();

    final parsed = ScanParser.parse(raw);
    final code = parsed.barcode;

    String? localName;
    BarcodeLookupResult? off;
    _ShelfLocation? shelfLoc;
    final palletLocs = <_PalletLocation>[];
    final localPhotos = <String>[];

    if (code != null) {
      // Yerel ad
      try {
        localName = await ref
            .read(barcodeDirectoryRepositoryProvider)
            .findProductName(code);
        localName ??= (await ref
                .read(productRepositoryProvider)
                .findByBarcode(code))
            ?.name;
      } catch (_) {}
      // OFF (gorsel + kategori + miktar + ad)
      try {
        off = await BarcodeLookupService.instance.lookupDetailed(code);
      } catch (_) {}
      // REYON KONUMU: urun bir reyonda kayitliysa "nerede" bilgisi.
      try {
        final units = await ShelfLayoutService.instance.getUnitSummaries();
        outer:
        for (final u in units) {
          final slots =
              await ShelfLayoutService.instance.getSlots(u.unit.id!);
          for (final s in slots) {
            if (s.barcode == code) {
              // Canlandirma izgarasi icin reyonun boyutlari:
              int maxRow = s.rowNo;
              for (final o in slots) {
                if (o.rowNo > maxRow) maxRow = o.rowNo;
              }
              shelfLoc = _ShelfLocation(
                unitName: u.unit.name,
                section: s.sectionNo,
                row: s.rowNo,
                cols: u.unit.sections,
                rows: maxRow,
                photoPath: s.photoPath,
                allUnits: units.map((x) => x.unit.name).toList(),
                unitIndex: units.indexOf(u),
              );
              break outer;
            }
          }
        }
      } catch (_) {}
      // YEREL FOTOGRAFLAR: Fiyat Kontrol'de bu barkod icin cekilmis
      // etiket/kanit fotograflari varsa (dosyasi hala mevcutsa) topla.
      // OFF'un ag gorseli yerine/yaninda oncelikli gosterilir.
      try {
        final history =
            await PriceChangeService.instance.lookupBarcodeHistory(code);
        for (final h in history) {
          final p = h.photoPath;
          if (p == null) continue;
          if (await File(p).exists()) {
            localPhotos.add(p);
            if (localPhotos.length >= 8) break;
          }
        }
      } catch (_) {}
      // DEPO (PALET) KONUMLARI: ayni urun depoda hangi paletlerde?
      // Reyon bos oldugunda "depoya bakmadan" cevap verebilmek icin.
      try {
        final whs = await WarehouseService.instance.getWarehouses();
        for (final w in whs) {
          final locs =
              await WarehouseService.instance.findProduct(w.id!, code);
          if (locs.isEmpty) continue;
          // Deponun izgara boyutu (canlandirma icin): raflarin max sutun/raf'i.
          int gc = 1, gr = 1;
          try {
            final shelves =
                await WarehouseService.instance.getShelves(w.id!);
            for (final sh in shelves) {
              if (sh.columnNo > gc) gc = sh.columnNo;
              if (sh.shelfNo > gr) gr = sh.shelfNo;
            }
          } catch (_) {}
          for (final l in locs) {
            palletLocs.add(_PalletLocation(
              warehouseName: w.name,
              palletName: l.pallet.code,
              shelfLabel: l.shelf != null
                  ? 'Sütun ${l.shelf!.columnNo} · Raf ${l.shelf!.shelfNo}'
                  : 'Zemin',
              quantity: l.item.quantity,
              colNo: l.shelf?.columnNo,
              shelfNo: l.shelf?.shelfNo,
              gridCols: gc,
              gridRows: gr,
              allWarehouses: whs.map((x) => x.name).toList(),
              warehouseIndex: whs.indexOf(w),
              palletPhotoPath: l.pallet.imagePath,
            ));
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    // App bar rengi: bir onceki taranan barkodla karsilastir.
    // Ilk tarama -> notr; ayni -> yesil; farkli -> kirmizi.
    Color barColor;
    if (code == null) {
      barColor = AppTheme.primary;
    } else if (_lastBarcode == null) {
      barColor = AppTheme.primary; // ilk tarama, notr
    } else if (_lastBarcode == code) {
      barColor = AppTheme.statusSafe; // ayni barkod -> yesil
    } else {
      barColor = AppTheme.statusExpired; // farkli barkod -> kirmizi
    }

    setState(() {
      _parsed = parsed;
      _localName = localName;
      _off = off;
      _shelfLoc = shelfLoc;
      _palletLocs = palletLocs;
      _localPhotos = localPhotos;
      _busy = false;
      _appBarColor = barColor;
      if (code != null) _lastBarcode = code; // sonraki karsilastirma icin
    });

    // KONUM CANLANDIRMASI: urunun reyondaki yeri bulunduysa "kamera inisi"
    // gosterisi OTOMATIK oynar (kullanici istegi). Karta dokununca da
    // yeniden oynatilabilir. Reyonda yoksa ama DEPODA varsa, tam ekran
    // depo canlandirmasi oynar (once genel bakis, sonra sola/saga kayma,
    // sonra sutun/raf/palete yakinlasma).
    if (shelfLoc != null && mounted) {
      _playLocationReveal(shelfLoc);
    } else if (palletLocs.isNotEmpty && mounted) {
      _playWarehouseReveal(palletLocs.first);
    }
  }

  void _playWarehouseReveal(_PalletLocation loc) {
    showWarehouseFlythrough(
      context,
      warehouseName: loc.warehouseName,
      cols: loc.gridCols,
      rows: loc.gridRows,
      targetCol: loc.colNo,
      targetRow: loc.shelfNo,
      palletCode: loc.palletName,
      shelfLabel: loc.shelfLabel,
      quantity: loc.quantity,
      productName: _localName ?? _off?.name,
      localPhotos: _localPhotos,
      palletPhotoPath: loc.palletPhotoPath,
      allWarehouses: loc.allWarehouses,
      targetWarehouseIndex: loc.warehouseIndex,
    );
  }

  void _playLocationReveal(_ShelfLocation loc) {
    // Ayarlar > Görünüm'den kapatılmışsa canlandırma atlanır; konum
    // bilgisi yine de karttaki düz metinle gösterilmeye devam eder.
    if (!LocationRevealPrefs.instance.enabled) return;
    showLocationFlythrough(
      context,
      title: loc.unitName,
      cols: loc.cols,
      rows: loc.rows,
      targetCol: loc.section,
      targetRow: loc.row,
      subtitle: 'Sütun ${loc.section} · Raf ${loc.row}',
      productName: _localName ?? _off?.name,
      photoPath: loc.photoPath,
      // MAGAZA kus bakisi: kamera once TUM reyonlari gorur, hedefe ucar.
      allAisles: loc.allUnits,
      targetAisleIndex: loc.unitIndex,
    );
  }

  Future<void> _rescan() async {
    setState(() {
      _parsed = null;
      _localName = null;
      _off = null;
      _shelfLoc = null;
      _palletLocs = const [];
      _localPhotos = const [];
      _scanning = true;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    // TARAMA MODUNDA: kamera onizlemesi status bar arkasina kadar uzanir.
    //   - extendBodyBehindAppBar: true -> body, AppBar arkasina uzanir
    //   - AppBar saydam, golge yok -> kamera ustte status bar'a degeer
    //   - status bar ikonlari beyaz (kamera koyu zemin)
    // SONUC MODUNDA: yesil/kirmizi animasyonlu renkli AppBar geri gelir.
    final isScanning = _parsed == null;
    final overlay = isScanning
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          )
        : AppTheme.systemBarForColor(_appBarColor);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: isScanning ? Colors.black : AppTheme.background,
        extendBodyBehindAppBar: isScanning,
        appBar: AppBar(
          title: const Text('Etiket İnceleme'),
          backgroundColor: isScanning ? Colors.transparent : _appBarColor,
          foregroundColor: Colors.white,
          elevation: isScanning ? 0 : null,
          systemOverlayStyle: overlay,
          flexibleSpace: isScanning
              ? null
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(color: _appBarColor),
                ),
        ),
        body: isScanning ? _buildScanner() : _buildResult(),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        const ScanOverlay(hint: 'Etiket QR veya barkodunu çerçeveye getirin'),
        if (_busy)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildResult() {
    final p = _parsed!;
    final off = _off;
    final displayName =
        _localName ?? (off?.found == true ? off!.name : null);
    final fmt = DateFormat('dd.MM.yyyy');
    final fmtTime = DateFormat('dd.MM.yyyy HH:mm');

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Urun basligi + gorsel
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.card(accentColor: AppTheme.primary),
                child: Row(
                  children: [
                    if (_localPhotos.isNotEmpty)
                      GestureDetector(
                        onTap: () => openPhotoGallery(
                          context,
                          items: _localPhotos
                              .map((p) => PhotoItem(
                                    filePath: p,
                                    title: displayName ?? 'Ürün Görseli',
                                  ))
                              .toList(),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          child: Image.file(
                            File(_localPhotos.first),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 64,
                              height: 64,
                              color: AppTheme.surfaceAlt,
                              child: Icon(Icons.inventory_2_rounded,
                                  color: AppTheme.textTertiary),
                            ),
                          ),
                        ),
                      )
                    else if (off?.imageUrl != null)
                      GestureDetector(
                        onTap: () => openImageZoom(
                          context,
                          networkUrl: off!.imageUrl!,
                          title: off.name ?? 'Ürün Görseli',
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                          child: CachedImage(
                            url: off!.imageUrl!,
                            width: 64,
                            height: 64,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceAlt,
                          borderRadius:
                              BorderRadius.circular(AppTheme.rSm),
                        ),
                        child: Icon(Icons.inventory_2_rounded,
                            color: AppTheme.textTertiary),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName ?? 'Bilinmeyen ürün',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _localName != null
                                ? 'Kayıtlardan'
                                : (off?.found == true
                                    ? 'İnternetten (OFF)'
                                    : 'İsim bulunamadı'),
                            style: TextStyle(
                              fontSize: 12,
                              color: displayName != null
                                  ? AppTheme.statusSafe
                                  : AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── ÜRÜN KONUMU (animasyonlu) ──
              // Barkod bir reyonda kayitliysa "nerede" bilgisi dikkat
              // cekecek sekilde gosterilir: karta yay ile giris + konum
              // pinine surekli nabiz (pulse) animasyonu.
              if (_shelfLoc != null)
                GestureDetector(
                  onTap: () => _playLocationReveal(_shelfLoc!),
                  child: _locationCard(_shelfLoc!),
                ),
              if (_shelfLoc != null) const SizedBox(height: 12),
              // Depodaki palet konumlari — reyon karti olmasa da gorunur.
              if (_palletLocs.isNotEmpty) _palletCard(),
              if (_shelfLoc != null || _palletLocs.isNotEmpty)
                const SizedBox(height: 16),

              // ETIKET VERILERI
              const SectionLabel('Etiket Verileri'),
              const SizedBox(height: 8),
              if (p.barcode != null)
                _row(Icons.qr_code_rounded, 'Barkod', p.barcode!,
                    monospace: true),
              if (p.price != null)
                _row(Icons.sell_rounded, 'Etiket Fiyatı',
                    '${p.price!.toStringAsFixed(2)} ₺',
                    color: AppTheme.statusSafe, big: true),
              if (p.expiryDate != null)
                _row(Icons.event_rounded, 'Fiyat Değişim Tarihi',
                    fmt.format(p.expiryDate!)),
              if (p.labelDateTime != null)
                _row(Icons.print_rounded, 'Basım Tarihi',
                    fmtTime.format(p.labelDateTime!)),
              if (p.kind == ScanKind.plainBarcode)
                _infoNote('Bu düz bir barkod — fiyat bilgisi içermiyor. '
                    'Yıldızlı etiket QR\'ı fiyat taşır.'),

              // OFF VERILERI
              if (off?.found == true) ...[
                const SizedBox(height: 16),
                const SectionLabel('İnternet Bilgisi (Open Food Facts)'),
                const SizedBox(height: 8),
                if (off!.brand != null)
                  _row(Icons.business_rounded, 'Marka', off.brand!),
                if (off.category != null)
                  _row(Icons.category_rounded, 'Kategori', off.category!),
                if (off.quantity != null)
                  _row(Icons.straighten_rounded, 'Miktar', off.quantity!),
              ],
            ],
          ),
        ),

        // Alt aksiyonlar
        Container(
          decoration:
              BoxDecoration(color: AppTheme.surface, boxShadow: AppTheme.shadowMd),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.barcode != null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                WebSearchScreen(query: p.barcode!),
                          ),
                        ),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text("İnternette Ara"),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _rescan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Yeni Etiket Okut',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Reyon konum karti — yayli giris, konum pini nabiz atar, sutun/raf
  /// rozetleri sirayla belirir. "Urun surada!" hissi.
  Widget _locationCard(_ShelfLocation loc) {
    Widget badge(String label, String value, int delayMs) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 11)),
            const SizedBox(width: 5),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      )
          .animate()
          .fadeIn(delay: delayMs.ms, duration: 250.ms)
          .slideY(begin: 0.4, delay: delayMs.ms, duration: 300.ms);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        boxShadow: AppTheme.glow(AppTheme.accent),
      ),
      child: Row(
        children: [
          // Nabiz atan konum pini.
          const Icon(Icons.location_on_rounded,
                  color: Colors.white, size: 34)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.25, 1.25),
                  duration: 700.ms,
                  curve: Curves.easeInOut),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ÜRÜN BURADA',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(loc.unitName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    badge('Sütun', '${loc.section}', 150),
                    badge('Raf', '${loc.row}', 300),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .scale(
            begin: const Offset(0.9, 0.9),
            duration: 450.ms,
            curve: Curves.elasticOut);
  }

  /// Depodaki palet konumlari karti — reyon kartinin sade kardesi.
  /// "Rafta yoksa depoda su paletlerde var" bilgisi.
  Widget _palletCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(accentColor: AppTheme.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.warehouse_rounded,
                  color: AppTheme.primary, size: 20),
              SizedBox(width: 8),
              Text('DEPODA',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 8),
          ..._palletLocs.take(4).map((l) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                // Palete dokun -> tam ekran DEPO canlandirmasi (zemindeki
                // paletler de artik oynatilabilir; izgara konumu yoksa
                // dogrudan "Zemin" olarak gosterilir).
                onTap: () => _playWarehouseReveal(l),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.warehouseName} · ${l.palletName} — '
                        '${l.shelfLabel}  (${l.quantity} adet)',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary),
                      ),
                    ),
                    const Icon(Icons.play_circle_outline_rounded,
                        size: 18, color: AppTheme.primary),
                  ],
                ),
              ),
            );
          }),
          if (_palletLocs.length > 4)
            Text('… ve ${_palletLocs.length - 4} palet daha',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textTertiary)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.15, duration: 300.ms);
  }

  Widget _row(IconData icon, String label, String value,
      {bool monospace = false, Color? color, bool big = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: (color ?? AppTheme.primary).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(icon, color: color ?? AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: big ? 20 : 14.5,
                        fontWeight:
                            big ? FontWeight.w900 : FontWeight.w700,
                        color: color ?? AppTheme.textPrimary,
                        fontFamily: monospace ? 'monospace' : null)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoNote(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.statusWarning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppTheme.statusWarning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.statusWarning, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// Taranan barkodun reyon konumu (reyon adi + sutun + raf) + canlandirma
/// icin izgara boyutlari ve urun fotografi.
class _ShelfLocation {
  final String unitName;
  final int section;
  final int row;
  final int cols; // reyonun sutun sayisi
  final int rows; // reyondaki en buyuk raf numarasi
  final String? photoPath;
  final List<String> allUnits; // MAGAZA gorunumu: tum reyon adlari
  final int unitIndex; // hedef reyonun listedeki sirasi
  const _ShelfLocation({
    required this.unitName,
    required this.section,
    required this.row,
    required this.cols,
    required this.rows,
    this.photoPath,
    this.allUnits = const [],
    this.unitIndex = 0,
  });
}

/// Urunun depodaki bir palet konumu (+ canlandirma icin izgara bilgisi).
class _PalletLocation {
  final String warehouseName;
  final String palletName;
  final String shelfLabel;
  final int quantity;
  final int? colNo; // raftaysa sutun (canlandirma icin); zeminde null
  final int? shelfNo; // raftaysa raf
  final int gridCols; // deponun izgara boyutu (max sutun)
  final int gridRows; // deponun izgara boyutu (max raf)
  final List<String> allWarehouses; // magaza gorunumu: tum depo adlari
  final int warehouseIndex;
  final String? palletPhotoPath; // paletin GERCEK fotografi (varsa)
  const _PalletLocation({
    required this.warehouseName,
    required this.palletName,
    required this.shelfLabel,
    required this.quantity,
    this.colNo,
    this.shelfNo,
    this.gridCols = 1,
    this.gridRows = 1,
    this.allWarehouses = const [],
    this.warehouseIndex = 0,
    this.palletPhotoPath,
  });
}
