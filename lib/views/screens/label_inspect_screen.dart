import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/theme/app_theme.dart';
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
      _busy = false;
      _appBarColor = barColor;
      if (code != null) _lastBarcode = code; // sonraki karsilastirma icin
    });
  }

  Future<void> _rescan() async {
    setState(() {
      _parsed = null;
      _localName = null;
      _off = null;
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
        // Ipucu
        Positioned(
          top: 24,
          left: 24,
          right: 24,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.92),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Text(
              'Raf etiketini veya barkodu okutun',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
        ),
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
                    if (off?.imageUrl != null)
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
