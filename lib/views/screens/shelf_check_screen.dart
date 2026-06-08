import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
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
  void initState() {
    super.initState();
    if (!widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.stop());
    }
  }

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

    // Dizinden ad sorgula.
    final name = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .findProductName(code);

    setState(() {
      _productBarcode = code;
      _productName = name;
      _refPrice = null;
    });

    await _showSheet(ShelfResultSheet(
      type: ShelfResultType.product,
      barcode: code,
      productName: name,
    ));

    setState(() => _phase = _Phase.label);
  }

  Future<void> _handleLabel(String raw) async {
    final parsed = ScanParser.parse(raw);
    final labelCode = _normalize(parsed.barcode ?? raw);
    final price = parsed.price;

    // Barkod uyusmuyor
    if (labelCode != _productBarcode) {
      await _showSheet(ShelfResultSheet(
        type: ShelfResultType.mismatch,
        barcode: labelCode,
        productBarcode: _productBarcode,
        productName: _productName,
      ));
      return;
    }

    // Eslesti - fiyat yok
    if (price == null) {
      await _showSheet(ShelfResultSheet(
        type: ShelfResultType.matchSame,
        barcode: labelCode,
        productName: _productName,
      ));
      return;
    }

    // Ilk fiyat -> referans
    if (_refPrice == null) {
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
    await _showSheet(ShelfResultSheet(
      type: ShelfResultType.matchSame,
      barcode: labelCode,
      productName: _productName,
      price: price,
      priceUpdateDate: parsed.expiryDate,
      printDate: parsed.labelDateTime,
    ));
  }

  Future<void> _showSheet(Widget sheet) async {
    if (!mounted) return;
    await showModalBottomSheet(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _circleBtn(Icons.flash_on_rounded,
                () => _controller.toggleTorch()),
            if (_productBarcode != null) ...[
              const SizedBox(width: 4),
              GoogleSearchButton(query: _productBarcode!, compact: true),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
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
                  onPressed: _reset,
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
