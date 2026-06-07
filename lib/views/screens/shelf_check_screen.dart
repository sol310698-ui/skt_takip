import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';

/// Reyon etiket kontrol ekrani.
/// Akis: once urun barkodu okunur -> sonra etiketler arka arkaya taranir.
/// Etiket barkodu urunle eslesmezse uyari. Eslesirse onceki etiket fiyatiyla
/// karsilastirir.
class ShelfCheckScreen extends StatefulWidget {
  final bool isActive;
  const ShelfCheckScreen({super.key, this.isActive = true});

  @override
  State<ShelfCheckScreen> createState() => _ShelfCheckScreenState();
}

enum _Phase { product, label }

class _CheckEvent {
  final String message;
  final Color color;
  final IconData icon;
  final DateTime time;
  _CheckEvent(this.message, this.color, this.icon) : time = DateTime.now();
}

class _ShelfCheckScreenState extends State<ShelfCheckScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
  );

  _Phase _phase = _Phase.product;
  bool _ean13Only = false;
  bool _busy = false;

  String? _productBarcode;     // okunan urun barkodu
  double? _lastLabelPrice;     // onceki etiketin fiyati
  final List<_CheckEvent> _events = [];

  @override
  void initState() {
    super.initState();
    if (!widget.isActive) {
      // Baslangicta sekme aktif degilse kamerayi durdur.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.stop();
      });
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

  /// EAN-13 sabitleme aciksa barkodu normalize et.
  String _normalize(String code) {
    if (!_ean13Only) return code;
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 13) return digits.substring(0, 13);
    return digits;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    _busy = true;
    await Future.delayed(const Duration(milliseconds: 400));

    if (_phase == _Phase.product) {
      _handleProduct(raw);
    } else {
      _handleLabel(raw);
    }

    if (mounted) setState(() {});
    await Future.delayed(const Duration(milliseconds: 800));
    _busy = false;
  }

  void _handleProduct(String raw) {
    final parsed = ScanParser.parse(raw);
    final code = _normalize(parsed.barcode ?? raw);
    _productBarcode = code;
    _phase = _Phase.label;
    _lastLabelPrice = null;
    _addEvent('Ürün okundu: $code\nŞimdi etiketleri tarayın',
        AppTheme.primary, Icons.inventory_2_outlined);
  }

  void _handleLabel(String raw) {
    final parsed = ScanParser.parse(raw);
    final labelCode = _normalize(parsed.barcode ?? raw);

    // 1) Barkod kiyasla
    if (labelCode != _productBarcode) {
      _addEvent(
        'UYUŞMUYOR!\nÜrün: $_productBarcode\nEtiket: $labelCode',
        const Color(0xFFD32F2F),
        Icons.error_outline,
      );
      return;
    }

    // 2) Eslesti - fiyat kontrolu
    final price = parsed.price;
    if (price == null) {
      _addEvent('Eşleşti ✓ (fiyat okunamadı)',
          const Color(0xFF388E3C), Icons.check_circle_outline);
      return;
    }

    if (_lastLabelPrice == null) {
      _lastLabelPrice = price;
      _addEvent(
        'Eşleşti ✓\nFiyat: ${price.toStringAsFixed(2)} ₺${_dateInfo(parsed)}',
        const Color(0xFF388E3C),
        Icons.check_circle,
      );
    } else if ((price - _lastLabelPrice!).abs() > 0.001) {
      _addEvent(
        'FİYAT FARKI!\nÖnceki: ${_lastLabelPrice!.toStringAsFixed(2)} ₺\nYeni: ${price.toStringAsFixed(2)} ₺${_dateInfo(parsed)}',
        const Color(0xFFF57C00),
        Icons.price_change_outlined,
      );
      _lastLabelPrice = price;
    } else {
      _addEvent(
        'Eşleşti ✓ Fiyat aynı: ${price.toStringAsFixed(2)} ₺',
        const Color(0xFF388E3C),
        Icons.check_circle,
      );
    }
  }

  String _dateInfo(ScanResult r) {
    final parts = <String>[];
    if (r.expiryDate != null) {
      parts.add('Fiyat güncelleme: ${DateFormat('dd.MM.yyyy').format(r.expiryDate!)}');
    }
    if (r.labelDateTime != null) {
      parts.add('Basım: ${DateFormat('dd.MM.yyyy HH:mm').format(r.labelDateTime!)}');
    }
    return parts.isEmpty ? '' : '\n${parts.join('\n')}';
  }

  void _addEvent(String msg, Color color, IconData icon) {
    _events.insert(0, _CheckEvent(msg, color, icon));
  }

  void _reset() {
    setState(() {
      _phase = _Phase.product;
      _productBarcode = null;
      _lastLabelPrice = null;
      _events.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Kamera
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.42,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                _buildScanOverlay(),
                _buildTopBar(),
              ],
            ),
          ),
          // Alt panel
          Expanded(child: _buildPanel()),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    final isProduct = _phase == _Phase.product;
    final color = isProduct ? AppTheme.primary : const Color(0xFF4CAF50);
    return Stack(
      children: [
        Center(
          child: Container(
            width: 240,
            height: 130,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isProduct ? '1. ÜRÜN barkodunu okutun' : '2. ETİKETLERİ okutun',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.flash_on, color: Colors.white),
              onPressed: () => _controller.toggleTorch(),
            ),
            const Spacer(),
            // EAN-13 switch
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
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

  Widget _buildPanel() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Durum cubugu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                      ),
                      if (_lastLabelPrice != null)
                        Text(
                          'Son fiyat: ${_lastLabelPrice!.toStringAsFixed(2)} ₺',
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
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Olay listesi
          Expanded(
            child: _events.isEmpty
                ? const Center(
                    child: Text('Henüz tarama yok',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _events.length,
                    itemBuilder: (context, i) => _eventCard(_events[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(_CheckEvent e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: e.color, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(e.icon, color: e.color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(e.message,
                style: TextStyle(
                    color: e.color == const Color(0xFF388E3C)
                        ? AppTheme.textPrimary
                        : e.color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4)),
          ),
          Text(DateFormat('HH:mm:ss').format(e.time),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
