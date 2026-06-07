import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/google_search_button.dart';
import 'shelf_alert_sheet.dart';

/// Reyon etiket kontrol ekrani.
/// Once urun barkodu okunur, sonra etiketler arka arkaya taranir.
/// Sorun varsa (barkod uyusmaz / fiyat farki) kayan pencere acilir.
class ShelfCheckScreen extends StatefulWidget {
  final bool isActive;
  const ShelfCheckScreen({super.key, this.isActive = true});

  @override
  State<ShelfCheckScreen> createState() => _ShelfCheckScreenState();
}

enum _Phase { product, label }

class _ShelfCheckScreenState extends State<ShelfCheckScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  _Phase _phase = _Phase.product;
  bool _ean13Only = false;
  bool _busy = false;
  bool _sheetOpen = false;

  String? _productBarcode;
  double? _lastLabelPrice;
  String _flash = ''; // anlik yesil onay mesaji
  Color _flashColor = const Color(0xFF388E3C);

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
    if (_busy || _sheetOpen) return;
    final raw =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    _busy = true;
    if (_phase == _Phase.product) {
      _handleProduct(raw);
    } else {
      await _handleLabel(raw);
    }
    await Future.delayed(const Duration(milliseconds: 700));
    _busy = false;
  }

  void _handleProduct(String raw) {
    final parsed = ScanParser.parse(raw);
    final code = _normalize(parsed.barcode ?? raw);
    setState(() {
      _productBarcode = code;
      _phase = _Phase.label;
      _lastLabelPrice = null;
      _showFlash('Ürün okundu, etiketleri tarayın', AppTheme.primary);
    });
  }

  Future<void> _handleLabel(String raw) async {
    final parsed = ScanParser.parse(raw);
    final labelCode = _normalize(parsed.barcode ?? raw);

    // Barkod uyusmuyor -> kayan pencere
    if (labelCode != _productBarcode) {
      await _openAlert(ShelfAlertSheet(
        type: ShelfAlertType.mismatch,
        productBarcode: _productBarcode ?? '',
        labelBarcode: labelCode,
      ));
      return;
    }

    final price = parsed.price;
    if (price == null) {
      setState(() => _showFlash('Eşleşti ✓ (fiyat yok)',
          const Color(0xFF388E3C)));
      return;
    }

    if (_lastLabelPrice == null) {
      setState(() {
        _lastLabelPrice = price;
        _showFlash('Eşleşti ✓  ${price.toStringAsFixed(2)} ₺',
            const Color(0xFF388E3C));
      });
    } else if ((price - _lastLabelPrice!).abs() > 0.001) {
      final old = _lastLabelPrice;
      _lastLabelPrice = price;
      await _openAlert(ShelfAlertSheet(
        type: ShelfAlertType.priceDiff,
        productBarcode: _productBarcode ?? '',
        labelBarcode: labelCode,
        oldPrice: old,
        newPrice: price,
        priceUpdateDate: parsed.expiryDate,
        printDate: parsed.labelDateTime,
      ));
    } else {
      setState(() => _showFlash('Eşleşti ✓ Fiyat aynı',
          const Color(0xFF388E3C)));
    }
  }

  void _showFlash(String msg, Color color) {
    _flash = msg;
    _flashColor = color;
  }

  Future<void> _openAlert(Widget sheet) async {
    _sheetOpen = true;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => sheet,
    );
    _sheetOpen = false;
    if (mounted) setState(() {});
  }

  void _reset() {
    setState(() {
      _phase = _Phase.product;
      _productBarcode = null;
      _lastLabelPrice = null;
      _flash = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProduct = _phase == _Phase.product;
    final frameColor =
        isProduct ? AppTheme.primary : const Color(0xFF4CAF50);

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
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: color.withOpacity(0.92),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                isProduct
                    ? '1. ÜRÜN barkodunu okutun'
                    : '2. ETİKETLERİ okutun',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 250,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 16),
            // Anlik yesil onay
            if (_flash.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _flashColor.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_flash,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
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
            IconButton(
              icon: const Icon(Icons.flash_on, color: Colors.white),
              onPressed: () => _controller.toggleTorch(),
            ),
            // Urun arama (eger urun okunduysa Google'da arat)
            if (_productBarcode != null)
              GoogleSearchButton(query: _productBarcode!, compact: true),
            const Spacer(),
            Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const Text('EAN-13',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Switch(
                    value: _ean13Only,
                    activeColor: AppTheme.primary,
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

  Widget _buildBottomStatus() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productBarcode == null
                          ? 'Ürün bekleniyor'
                          : 'Ürün: $_productBarcode',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_lastLabelPrice != null)
                      Text(
                        'Referans fiyat: ${_lastLabelPrice!.toStringAsFixed(2)} ₺',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13),
                      ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Yeni Ürün'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
