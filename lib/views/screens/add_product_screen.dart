import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/image_preprocess_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../core/utils/scan_parser.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import 'precise_scan_screen.dart';
import 'web_search_screen.dart';

/// Tam ekran urun formu (ekleme + duzenleme). Akilli ozellikler:
/// - Barkod yazilinca/tarayinca canli isim+detay cekme (dizin -> urunler -> OFF)
/// - OFF'tan kategori, marka, gorsel onizleme
/// - SKT icin OCR / hassas tarama / takvim kisayollari
class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? existing;
  final DateTime? scannedExpiry;
  final String? prefillBarcode;
  final String? prefillName;

  const ProductFormScreen({
    super.key,
    this.existing,
    this.scannedExpiry,
    this.prefillBarcode,
    this.prefillName,
  });

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _categoryCtrl;
  late int _quantity;
  DateTime? _expiryDate;

  // Akilli arama durumu
  Timer? _debounce;
  bool _looking = false;
  String? _lookupInfo;      // kullaniciya gosterilen kisa durum metni
  String? _previewImageUrl; // OFF urun gorseli
  String _lastLookedUp = ''; // ayni barkodu tekrar sorgulamamak icin

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl =
        TextEditingController(text: e?.name ?? widget.prefillName ?? '');
    _barcodeCtrl =
        TextEditingController(text: e?.barcode ?? widget.prefillBarcode ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _quantity = e?.quantity ?? 1;
    _expiryDate = widget.scannedExpiry ?? e?.expiryDate;

    // Barkod onceden geldi ve isim bossa, acilista bir kez akilli arama yap.
    final initialBarcode = _barcodeCtrl.text.trim();
    if (initialBarcode.isNotEmpty && _nameCtrl.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _smartLookup(initialBarcode);
      });
    }

    // Barkod alani elle degisince debounce'lu arama.
    _barcodeCtrl.addListener(_onBarcodeChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _barcodeCtrl.removeListener(_onBarcodeChanged);
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _onBarcodeChanged() {
    final code = _barcodeCtrl.text.trim();
    _debounce?.cancel();
    if (!ScanResult.looksLikeBarcode(code)) return;
    if (code == _lastLookedUp) return;
    // Kullanici yazmayi bitirince ara.
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _smartLookup(code);
    });
  }

  /// Kademeli akilli arama: dizin -> aktif urunler -> Open Food Facts.
  /// Isim bos VEYA kullanici henuz girmemisse doldurur; kategori/gorsel ekler.
  Future<void> _smartLookup(String rawCode) async {
    final code = rawCode.trim();
    if (!ScanResult.looksLikeBarcode(code)) return;
    _lastLookedUp = code;

    setState(() {
      _looking = true;
      _lookupInfo = null;
    });

    String? name;
    String? category;

    // 1) Yerel dizin
    try {
      name = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .findProductName(code);
    } catch (_) {}

    // 2) Aktif/gecmis urunler
    if (name == null) {
      try {
        final p =
            await ref.read(productRepositoryProvider).findByBarcode(code);
        if (p != null) {
          name = p.name;
          category = p.category;
        }
      } catch (_) {}
    }

    String? info;
    String? imageUrl;

    // 3) Open Food Facts
    if (name == null) {
      try {
        final r = await BarcodeLookupService.instance.lookupDetailed(code);
        if (r.found) {
          name = r.name;
          category = r.category;
          imageUrl = r.imageUrl;
          info = 'İnternetten bulundu';
        } else {
          switch (r.status) {
            case BarcodeLookupStatus.notFound:
              info = 'İnternette de bulunamadı';
              break;
            case BarcodeLookupStatus.timeout:
              info = 'İnternet yanıt vermedi';
              break;
            default:
              info = 'İnternetten alınamadı';
          }
        }
      } catch (_) {
        info = 'İnternetten alınamadı';
      }
    } else {
      info = 'Kayıtlardan bulundu';
    }

    if (!mounted) return;
    setState(() {
      _looking = false;
      _lookupInfo = info;
      _previewImageUrl = imageUrl;
      // Isim alani bossa doldur (kullanicinin yazdigini ezme).
      if (name != null && _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = name;
      }
      if (category != null && _categoryCtrl.text.trim().isEmpty) {
        _categoryCtrl.text = category;
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  /// Fotograf cekerek SKT oku (ML Kit + akilli parser).
  Future<void> _scanDateFromPhoto() async {
    final picker = ImagePicker();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    List<String> variants = [];
    String? originalPath;
    try {
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (photo == null) return;
      originalPath = photo.path;

      variants =
          await ImagePreprocessService.instance.generateVariants(photo.path);

      final texts = <String>[];
      for (final path in variants) {
        try {
          final input = InputImage.fromFilePath(path);
          final result = await recognizer.processImage(input);
          if (result.text.isNotEmpty) texts.add(result.text);
        } catch (_) {}
      }

      final date = du.DateUtils.parseFromMultiple(texts);

      if (!mounted) return;
      if (date != null) {
        setState(() => _expiryDate = date);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Tarih okundu: ${DateFormat('dd.MM.yyyy').format(date)}'),
            backgroundColor: AppTheme.statusSafe,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tarih okunamadı, takvimden seçebilirsiniz'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      recognizer.close();
      if (originalPath != null) {
        await ImagePreprocessService.instance.cleanup(variants, originalPath);
      }
    }
  }

  /// Hassas (foto-cek + on isleme + aday listesi) SKT tarama.
  Future<void> _preciseDate() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const PreciseScanScreen()),
    );
    if (result != null && result.year != 1900 && mounted) {
      setState(() => _expiryDate = result);
    }
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

  void _searchOnline() {
    final barcode = _barcodeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final query = barcode.isNotEmpty ? barcode : name;
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce barkod veya ürün adı girin')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebSearchScreen(query: query)),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen SKT seçin')),
      );
      return;
    }

    final notifier = ref.read(productListProvider.notifier);
    final base = widget.existing;

    final product = Product(
      id: base?.id,
      name: _nameCtrl.text.trim(),
      barcode:
          _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      expiryDate: _expiryDate!,
      quantity: _quantity,
      category: _categoryCtrl.text.trim().isEmpty
          ? null
          : _categoryCtrl.text.trim(),
      createdAt: base?.createdAt ?? DateTime.now(),
    );

    int savedId;
    if (base == null) {
      savedId = await notifier.add(product);
    } else {
      await notifier.updateProduct(product);
      savedId = base.id!;
      await NotificationService.instance.cancelForProduct(savedId);
    }

    await NotificationService.instance
        .scheduleForProduct(product.copyWith(id: savedId));

    // Barkod + ad varsa VE barkod gecerli formattaysa dizine de yaz.
    if (product.barcode != null &&
        product.name.isNotEmpty &&
        ScanResult.looksLikeBarcode(product.barcode!)) {
      await ref.read(barcodeDirectoryRepositoryProvider).importAll([
        BarcodeEntry(
          barcode: product.barcode!,
          productName: product.name,
          importedAt: DateTime.now(),
        ),
      ]);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final dateStr = _expiryDate == null
        ? 'SKT seçilmedi'
        : DateFormat('dd.MM.yyyy').format(_expiryDate!);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Ürün Düzenle' : 'Yeni Ürün'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(isEdit ? 'Güncelle' : 'Kaydet'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // OFF gorsel onizleme + durum
            if (_previewImageUrl != null || _looking || _lookupInfo != null)
              _buildPreview(),

            // Urun adi
            TextFormField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Ürün adı *',
                prefixIcon: Icon(Icons.shopping_bag_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
            ),
            const SizedBox(height: 16),

            // Barkod + tara + ara
            TextFormField(
              controller: _barcodeCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Barkod',
                prefixIcon: const Icon(Icons.qr_code_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_looking)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else ...[
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: "Google'da Ara",
                        onPressed: _searchOnline,
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'Barkod Tara',
                        onPressed: _scanBarcode,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Kategori
            TextFormField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                labelText: 'Kategori / Reyon',
                prefixIcon: Icon(Icons.category_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // SKT secimi - takvim + kamera + hassas
            _buildExpirySection(dateStr),
            const SizedBox(height: 16),

            // Adet
            _buildQuantitySelector(),
            const SizedBox(height: 28),

            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(isEdit ? 'Güncelle' : 'Kaydet',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          // Gorsel
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _previewImageUrl != null
                ? Image.network(
                    _previewImageUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imgPlaceholder(),
                    loadingBuilder: (c, w, p) =>
                        p == null ? w : _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                if (_looking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_looking) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _looking
                        ? 'Ürün bilgisi aranıyor...'
                        : (_lookupInfo ?? ''),
                    style: TextStyle(
                      fontSize: 13,
                      color: _lookupInfo == 'İnternetten bulundu' ||
                              _lookupInfo == 'Kayıtlardan bulundu'
                          ? AppTheme.statusSafe
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.inventory_2_outlined,
          color: AppTheme.textTertiary, size: 28),
    );
  }

  Widget _buildExpirySection(String dateStr) {
    final hasDate = _expiryDate != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(
          accentColor: hasDate ? AppTheme.primary : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_rounded,
                  color: hasDate ? AppTheme.primary : AppTheme.textSecondary,
                  size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Son Kullanma: $dateStr',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: hasDate
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: const Text('Takvim'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanDateFromPhoto,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Foto'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _preciseDate,
                  icon: const Icon(Icons.center_focus_strong_rounded,
                      size: 18),
                  label: const Text('Hassas'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary.withOpacity(0.85),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuantitySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Adet', style: TextStyle(fontSize: 15)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed:
                    _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              Text('$_quantity',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _quantity++),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final value = barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barkod Tara')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 60,
            child: Text(
              'Barkodu çerçeveye getirin',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
