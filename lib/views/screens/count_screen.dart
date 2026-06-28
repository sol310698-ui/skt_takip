import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/control_list_item.dart';
import '../../viewmodels/providers.dart';

/// ════════════════════════════════════════════════════════════════════
///  SAYIM (EL TERMINALI TARZI)
/// ────────────────────────────────────────────────────────────────────
///  Akis (kesintisiz, tek elle):
///    1. Kamera surekli acik, barkod bekler.
///    2. Barkod okutulur -> kontrol listesinde aranir.
///       - Bulunursa: urun adi + adet kutusu acilir (otomatik odak).
///       - Bulunamazsa: kisa uyari, kamera devam eder.
///    3. Adet girilir (orn. 50), "Kaydet" (veya klavye Enter) -> kaydedilir.
///    4. Kamera tekrar hazir; siradaki urun.
///
///  Ayni urun tekrar okutulursa: SON girilen adet gecerlidir (uzerine yazar).
///  Bu, el terminallerinin standart davranisidir.
/// ════════════════════════════════════════════════════════════════════
class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({super.key});

  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  final TextEditingController _qtyController = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();

  List<ControlListItem> _items = [];
  bool _loading = true;

  // O an okutulan, adedi beklenen urun.
  ControlListItem? _active;
  bool _scanPaused = false;

  // Son kaydedilen (geri bildirim icin).
  String? _lastSavedName;
  int? _lastSavedQty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _qtyController.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ref.read(controlListRepositoryProvider).getAll();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  int get _countedCount => _items.where((e) => e.isCounted).length;
  int get _totalQty =>
      _items.fold(0, (sum, e) => sum + (e.countedQty ?? 0));

  void _onDetect(BarcodeCapture capture) {
    if (_scanPaused || _active != null) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      _handleBarcode(raw);
      return;
    }
  }

  void _handleBarcode(String code) {
    // Kontrol listesinde bu barkodu ara.
    final idx = _items.indexWhere((e) {
      final bc = e.barcode?.trim();
      return bc != null && bc == code;
    });

    if (idx == -1) {
      // Listede yok — kisa uyari, kamera devam.
      HapticFeedback.heavyImpact();
      setState(() {
        _lastSavedName = '✗ Listede yok: $code';
        _lastSavedQty = null;
      });
      return;
    }

    // Bulundu — adet girisi icin duraklat, kutu ac.
    HapticFeedback.mediumImpact();
    setState(() {
      _active = _items[idx];
      _scanPaused = true;
      // Onceki sayim varsa kutuya getir (uzerine yazma kolayligi).
      _qtyController.text = _items[idx].countedQty?.toString() ?? '';
    });
    // Klavyeyi ac + secili yap.
    Future.delayed(const Duration(milliseconds: 100), () {
      _qtyFocus.requestFocus();
      _qtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyController.text.length,
      );
    });
  }

  Future<void> _saveQty() async {
    final active = _active;
    if (active == null || active.id == null) return;
    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty < 0) {
      HapticFeedback.heavyImpact();
      return;
    }

    await ref.read(controlListRepositoryProvider).setCount(active.id!, qty);

    // Yerel listeyi guncelle.
    final idx = _items.indexWhere((e) => e.id == active.id);
    if (idx != -1) {
      _items[idx] = _items[idx].copyWith(
        countedQty: qty,
        countedAt: DateTime.now(),
        checked: true,
      );
    }

    HapticFeedback.lightImpact();
    setState(() {
      _lastSavedName = active.productName ?? active.barcode ?? '';
      _lastSavedQty = qty;
      _active = null;
      _scanPaused = false;
      _qtyController.clear();
    });
  }

  void _cancelEntry() {
    setState(() {
      _active = null;
      _scanPaused = false;
      _qtyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sayım'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'El feneri',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _emptyState(cs)
              : Column(
                  children: [
                    _statsBar(),
                    Expanded(child: _scannerArea(cs)),
                    if (_active != null) _qtyEntry(cs) else _lastSavedBar(cs),
                  ],
                ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56, color: cs.onSurface.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Sayım için kontrol listesi boş.\n'
              'Önce Excel veya fotoğraf ile ürün listesi yükleyin.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.primary.withOpacity(0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('Sayılan', '$_countedCount/${_items.length}'),
          _stat('Toplam Adet', '$_totalQty'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _scannerArea(ColorScheme cs) {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // Hedef cercevesi.
        Container(
          width: 250,
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(
                color: _active != null ? Colors.orange : Colors.greenAccent,
                width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Text(
            _active != null
                ? 'Adet girin'
                : 'Ürün barkodunu okutun',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _qtyEntry(ColorScheme cs) {
    final active = _active!;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(active.productName ?? '(isimsiz ürün)',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Barkod: ${active.barcode ?? "-"}',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  focusNode: _qtyFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveQty(),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Adet',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: AppTheme.primary.withOpacity(0.05),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _saveQty,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.statusSuccess,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: const Text('Kaydet',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _cancelEntry,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('İptal (okutmaya devam et)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lastSavedBar(ColorScheme cs) {
    final isError = _lastSavedQty == null && _lastSavedName != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: _lastSavedName == null
          ? cs.surface
          : (isError
              ? AppTheme.statusWarning.withOpacity(0.15)
              : AppTheme.statusSuccess.withOpacity(0.12)),
      child: _lastSavedName == null
          ? Text('Okutmaya hazır — bir ürün barkodu okutun.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withOpacity(0.6)))
          : Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline
                      : Icons.check_circle_rounded,
                  color: isError
                      ? AppTheme.statusWarning
                      : AppTheme.statusSuccess,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isError
                        ? _lastSavedName!
                        : '$_lastSavedName → $_lastSavedQty adet kaydedildi',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
    );
  }
}
