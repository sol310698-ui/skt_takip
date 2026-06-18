import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';
import 'add_product_screen.dart'; // BarcodeScanPage

/// Hizli barkod + urun adi kayit sayfasi (barkod dizini icin).
/// SKT/adet/kategori yok — reyon kontrol ve barkod listesi kaydina ozel.
class BarcodeEntryScreen extends ConsumerStatefulWidget {
  final String? prefillBarcode;
  final String? prefillName;

  const BarcodeEntryScreen({
    super.key,
    this.prefillBarcode,
    this.prefillName,
  });

  @override
  ConsumerState<BarcodeEntryScreen> createState() =>
      _BarcodeEntryScreenState();
}

class _BarcodeEntryScreenState extends ConsumerState<BarcodeEntryScreen> {
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _stockCtrl;
  bool _looking = false;
  bool _saving = false;
  String? _lookupInfo;
  Timer? _debounce;
  String _lastLookedUp = '';

  @override
  void initState() {
    super.initState();
    _barcodeCtrl =
        TextEditingController(text: widget.prefillBarcode ?? '');
    _nameCtrl = TextEditingController(text: widget.prefillName ?? '');
    _stockCtrl = TextEditingController();
    _barcodeCtrl.addListener(_onBarcodeChanged);

    // Barkod onceden geldi, isim bossa hemen ara.
    final code = _barcodeCtrl.text.trim();
    if (code.isNotEmpty && _nameCtrl.text.trim().isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _smartLookup(code));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _barcodeCtrl.removeListener(_onBarcodeChanged);
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  void _onBarcodeChanged() {
    final code = _barcodeCtrl.text.trim();
    _debounce?.cancel();
    if (!ScanResult.looksLikeBarcode(code) || code == _lastLookedUp) return;
    _debounce = Timer(
        const Duration(milliseconds: 600), () => _smartLookup(code));
  }

  Future<void> _smartLookup(String rawCode) async {
    final code = rawCode.trim();
    if (!ScanResult.looksLikeBarcode(code)) return;
    _lastLookedUp = code;
    setState(() { _looking = true; _lookupInfo = null; });

    String? name;
    // 1) Yerel dizin (stok kodu varsa onu da getir)
    try {
      final entry = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .findEntryByBarcode(code);
      if (entry != null) {
        name = entry.productName;
        if (entry.stockCode != null &&
            entry.stockCode!.isNotEmpty &&
            _stockCtrl.text.trim().isEmpty) {
          _stockCtrl.text = entry.stockCode!;
        }
      }
    } catch (_) {}
    // 2) Aktif urunler
    if (name == null) {
      try {
        name = (await ref.read(productRepositoryProvider).findByBarcode(code))
            ?.name;
      } catch (_) {}
    }
    // 3) OFF
    String? info;
    if (name == null) {
      try {
        final r = await BarcodeLookupService.instance.lookupDetailed(code);
        if (r.found && r.name != null) {
          name = r.name;
          info = 'İnternetten bulundu';
        } else {
          _lastLookedUp = '';
          info = 'Bulunamadı';
        }
      } catch (_) {
        _lastLookedUp = '';
        info = 'İnternet hatası';
      }
    } else {
      info = 'Kayıtlardan bulundu';
    }

    if (!mounted) return;
    setState(() {
      _looking = false;
      _lookupInfo = info;
      if (name != null && _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = name;
      }
    });
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code != null && mounted) {
      _barcodeCtrl.text = code;
      _smartLookup(code);
    }
  }

  Future<void> _save() async {
    final barcode = _barcodeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final stock = _stockCtrl.text.trim();
    if (barcode.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barkod ve ürün adı zorunlu')),
      );
      return;
    }
    if (!ScanResult.looksLikeBarcode(barcode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz barkod formatı')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(barcodeDirectoryRepositoryProvider).importAll([
        BarcodeEntry(
          barcode: barcode,
          productName: name,
          stockCode: stock.isEmpty ? null : stock,
          importedAt: DateTime.now(),
          source: BarcodeSource.manual,
        ),
      ]);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürün Kaydet'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // Arama durumu
          if (_looking || _lookupInfo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: AppTheme.card(),
              child: Row(
                children: [
                  if (_looking)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primary),
                    )
                  else
                    Icon(
                      _lookupInfo!.contains('bulundu')
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color: _lookupInfo!.contains('bulundu')
                          ? AppTheme.statusSafe
                          : AppTheme.textSecondary,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _looking ? 'Aranıyor...' : _lookupInfo ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: _lookupInfo != null &&
                                _lookupInfo!.contains('bulundu')
                            ? AppTheme.statusSafe
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SectionLabel('Barkod'),
          const SizedBox(height: 8),
          TextField(
            controller: _barcodeCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Barkod numarası',
              prefixIcon: _looking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primary),
                      ),
                    )
                  : const Icon(Icons.qr_code_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Tara',
                onPressed: _scanBarcode,
              ),
            ),
          ),

          const SizedBox(height: 20),
          const SectionLabel('Ürün Adı'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              hintText: 'Ürün adı',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
            ),
            textInputAction: TextInputAction.next,
          ),

          const SizedBox(height: 20),
          const SectionLabel('Stok Kodu (opsiyonel)'),
          const SizedBox(height: 8),
          TextField(
            controller: _stockCtrl,
            decoration: const InputDecoration(
              hintText: 'Stok kodu (Excel ile eşleşir)',
              prefixIcon: Icon(Icons.tag_rounded),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppTheme.textTertiary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bu kayıt sadece barkod dizinine eklenir. '
                    'SKT takibi için ana ekrandan "SKT Tara" kullanın.',
                    style: TextStyle(
                        color: AppTheme.textTertiary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          boxShadow: AppTheme.shadowMd,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Listeye Kaydet',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ),
      ),
    );
  }
}
