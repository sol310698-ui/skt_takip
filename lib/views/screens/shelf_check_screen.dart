import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/shelf_session_service.dart';
import 'barcode_entry_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/google_search_button.dart';
import 'shelf_result_sheet.dart';

/// Reyon etiket kontrol ekrani.
/// 1) Urun barkodu okunur -> kayan pencere onayi
/// 2) Etiketler arka arkaya okunur -> her birinde kayan pencere
/// Pencere acikken kamera durur, kapaninca devam eder.
class ShelfCheckScreen extends ConsumerStatefulWidget {
  final bool isActive;
  const ShelfCheckScreen({super.key, this.isActive = true});

  @override
  ConsumerState<ShelfCheckScreen> createState() => _ShelfCheckScreenState();
}

enum _Phase { product, label }

class _ShelfCheckScreenState extends ConsumerState<ShelfCheckScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  _Phase _phase = _Phase.product;
  bool _ean13Only = false;
  bool _busy = false;

  String? _productBarcode;
  String? _productName;
  double? _refPrice;

  @override
@override
  void initState() {
    super.initState();
    if (!widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.stop());
    }
  }
    ShelfSessionService.instance.start();

  @override
  void didUpdateWidget(ShelfCheckScreen old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _controller.start();
    } else if (!widget.isActive && old.isActive) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    ShelfSessionService.instance.finish();
    super.dispose();
  }

  String _normalize(String code) {
    if (!_ean13Only) return code;
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 13 ? digits.substring(0, 13) : digits;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    _busy = true;
    await _controller.stop();

    if (_phase == _Phase.product) {
      await _handleProduct(raw);
    } else {
      await _handleLabel(raw);
    }

    // Pencere kapandi -> kameraya devam.
    if (mounted && widget.isActive) {
      await _controller.start();
    }
    await Future.delayed(const Duration(milliseconds: 300));
    _busy = false;
  }

  Future<void> _handleProduct(String raw) async {
    final parsed = ScanParser.parse(raw);
    final code = _normalize(parsed.barcode ?? raw);

    // 1+2) Yerel arama aninda; pencereyi bekletme.
    String? name;
    bool inDirectory = false;
    try {
      name = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .findProductName(code);
      if (name != null) inDirectory = true;
    } catch (_) {}

    if (name == null) {
      try {
        name = (await ref.read(productRepositoryProvider)
                .findByBarcode(code))
            ?.name;
      } catch (_) {}
    }

    setState(() {
      _productBarcode = code;
      _productName = name;
      _refPrice = null;
    });

    // Pencere yerel sonucla HEMEN acilir (OFF beklenmez).
    // Arka planda OFF dener (2s timeout); isim geldiyse snackbar gosterir.
    if (name == null) {
      _lookupOffInBackground(code);
    }

    await _showSheet(ShelfResultSheet(
      type: ShelfResultType.product,
      barcode: code,
      productName: name,
      // Dizinde yoksa BarcodeEntryScreen ile hizli kayit sun.
      onSaveToDb: !inDirectory
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BarcodeEntryScreen(
                  prefillBarcode: code,
                  prefillName: name,
                ),
              ))
          : null,
    ));

    setState(() => _phase = _Phase.label);
  }

  /// OFF sorgusu tamamen arka planda; kullaniciya kisa snackbar.
  /// Reyon hizli akisi engellemez; timeout 2sn.
  Future<void> _lookupOffInBackground(String code) async {
    try {
      final r = await BarcodeLookupService.instance
          .lookupDetailed(code)
          .timeout(const Duration(seconds: 2));
      if (r.found && r.name != null && mounted) {
        setState(() => _productName = r.name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ürün: ${r.name}'),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    } catch (_) {
      // Timeout veya hata: sessizce yoksay, reyon akisini bloke etme.
    }
  }

  /// Reyon kontrolde okunan urunu barkod dizinine hizlica kaydeder.
  Future<void> _quickSaveToDirectory(String code, String name) async {
    if (!ScanResult.looksLikeBarcode(code)) return;
    try {
      await ref.read(barcodeDirectoryRepositoryProvider).importAll([
        BarcodeEntry(
          barcode: code,
          productName: name,
          importedAt: DateTime.now(),
        ),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" listeye kaydedildi'),
            backgroundColor: AppTheme.statusSafe,
            duration: const Duration(milliseconds: 1200),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _handleLabel(String raw) async {
    final parsed = ScanParser.parse(raw);
    final labelCode = _normalize(parsed.barcode ?? raw);
    final price = parsed.price;

    // Etiket fazinda DUZ bir urun barkodu (yildizsiz) okundu ve mevcut
    // urunden farkliysa: kullanici buyuk olasilikla yeni bir urune geciyor.
    if (parsed.kind == ScanKind.plainBarcode &&
        labelCode != _productBarcode) {
      final goNew = await _showSheet(ShelfResultSheet(
        type: ShelfResultType.newProduct,
        barcode: labelCode,
        productBarcode: _productBarcode,
        productName: _productName,
      ));
      if (goNew == true) {
        // Yeni urune gec: faz product gibi davranip bu kodu urun yap.
        await _handleProduct(raw);
      }
      return;
    }

    // Barkod uyusmuyor (etiket QR'i ama baska urune ait)
    if (labelCode != _productBarcode) {
      ShelfSessionService.instance.record(mismatched: true);
      await _showSheet(ShelfResultSheet(
        type: ShelfResultType.mismatch,
        barcode: labelCode,
        productBarcode: _productBarcode,
        productName: _productName,
      ));
      return;
    }

    // Eslesti ama etikette fiyat YOK.
    if (price == null) {
      ShelfSessionService.instance.record(noPrice: true);
      await _showSheet(ShelfResultSheet(
        type: ShelfResultType.noPrice,
        barcode: labelCode,
        productName: _productName,
      ));
      return;
    }

    // Ilk fiyat -> referans
    if (_refPrice == null) {
      ShelfSessionService.instance.record(matched: true);
      setState(() => _refPrice = price);
      await _showSheet(ShelfResultSheet(
        type: ShelfResultType.matchFirst,
        barcode: labelCode,
        productName: _productName,
        price: price,
        priceUpdateDate: parsed.expiryDate,
        printDate: parsed.labelDateTime,
      ));
      return;
    }

    // Fiyat farkli
    if ((price - _refPrice!).abs() > 0.001) {
      ShelfSessionService.instance.record(priceDiff: true);
      final old = _refPrice;
      setState(() => _refPrice = price);
      await _showSheet(ShelfResultSheet(
        type: ShelfResultType.priceDiff,
        barcode: labelCode,
        productName: _productName,
        price: price,
        oldPrice: old,
        priceUpdateDate: parsed.expiryDate,
        printDate: parsed.labelDateTime,
      ));
      return;
    }

    // Fiyat ayni
    ShelfSessionService.instance.record(matched: true);
    await _showSheet(ShelfResultSheet(
      type: ShelfResultType.matchSame,
      barcode: labelCode,
      productName: _productName,
      price: price,
      priceUpdateDate: parsed.expiryDate,
      printDate: parsed.labelDateTime,
    ));
  }

  /// Sheet'i gosterir; newProduct gibi karar gerektiren tiplerde bool doner.
  Future<bool?> _showSheet(Widget sheet) async {
    if (!mounted) return null;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => sheet,
    );
  }

  void _reset() {
    setState(() {
      _phase = _Phase.product;
      _productBarcode = null;
      _productName = null;
      _refPrice = null;
    });
  }

  Future<void> _showSessionSummary(ShelfSession session) async {
    final dur = session.duration;
    final mins = dur.inMinutes;
    final secs = dur.inSeconds % 60;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.analytics_rounded,
                    color: AppTheme.accent, size: 22),
                SizedBox(width: 10),
                Text('Oturum Özeti',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 16),
            _summaryRow(Icons.qr_code_scanner_rounded,
                'Taranan etiket', '${session.scannedCount}',
                AppTheme.textPrimary),
            _summaryRow(Icons.check_circle_rounded,
                'Eşleşen', '${session.matchCount}',
                AppTheme.statusSafe),
            if (session.priceDiffCount > 0)
              _summaryRow(Icons.price_change_rounded,
                  'Fiyat farkı', '${session.priceDiffCount}',
                  AppTheme.statusWarning),
            if (session.mismatchCount > 0)
              _summaryRow(Icons.error_rounded,
                  'Uyuşmayan', '${session.mismatchCount}',
                  AppTheme.statusExpired),
            if (session.noPriceCount > 0)
              _summaryRow(Icons.help_outline_rounded,
                  'Fiyat okunamadı', '${session.noPriceCount}',
                  AppTheme.textSecondary),
            const Divider(height: 24),
            _summaryRow(Icons.timer_rounded,
                'Süre', '$mins dk $secs sn',
                AppTheme.textSecondary),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppTheme.textSecondary))),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProduct = _phase == _Phase.product;
    final frameColor = isProduct ? AppTheme.primary : AppTheme.statusSafe;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _buildOverlay(frameColor, isProduct),
          _buildTopControls(),
          _buildBottomStatus(),
        ],
      ),
    );
  }

  Widget _buildOverlay(Color color, bool isProduct) {
    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      isProduct
                          ? Icons.inventory_2_rounded
                          : Icons.sell_rounded,
                      color: Colors.white,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isProduct ? 'ÜRÜN barkodunu okut' : 'ETİKETLERİ okut',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: 256,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _circleBtn(Icons.flash_on_rounded,
                    () => _controller.toggleTorch()),
                if (_productBarcode != null) ...[
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.black.withOpacity(0.6),
                    shape: const CircleBorder(),
                    child: GoogleSearchButton(
                        query: _productBarcode!, compact: true),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.only(left: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('EAN-13',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Switch(
                        value: _ean13Only,
                        activeColor: AppTheme.accent,
                        onChanged: (v) => setState(() => _ean13Only = v),
                      ),
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

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildBottomStatus() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _productBarcode == null
                      ? AppTheme.surfaceAlt
                      : AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _productBarcode == null
                      ? Icons.qr_code_scanner_rounded
                      : Icons.check_circle_rounded,
                  color: _productBarcode == null
                      ? AppTheme.textTertiary
                      : AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productBarcode == null
                          ? 'Ürün bekleniyor'
                          : (_productName ?? _productBarcode!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_refPrice != null)
                      Text('Referans: ${_refPrice!.toStringAsFixed(2)} ₺',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12.5))
                    else if (_productBarcode != null)
                      Text(_productBarcode!,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12.5,
                              fontFamily: 'monospace')),
                  ],
                ),
              ),
              if (_productBarcode != null)
                FilledButton.icon(
                  onPressed: () async {
                    final finished =
                        await ShelfSessionService.instance.finish();
                    if (mounted && finished != null &&
                        finished.scannedCount > 0) {
                      await _showSessionSummary(finished);
                    }
                    await ShelfSessionService.instance.start();
                    _reset();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yeni'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
