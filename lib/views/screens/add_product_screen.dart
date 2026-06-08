import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/barcode_entry.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
/// Kayan pencere (bottom sheet) icinde calisan urun formu.
/// Yeni ekleme ve duzenleme icin kullanilir.
class ProductFormSheet extends ConsumerStatefulWidget {
  final Product? existing;
  final DateTime? scannedExpiry;
  final String? prefillBarcode;
  final String? prefillName;

  const ProductFormSheet({
    super.key,
    this.existing,
    this.scannedExpiry,
    this.prefillBarcode,
    this.prefillName,
  });

  @override
  ConsumerState<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _categoryCtrl;
  late int _quantity;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl =
        TextEditingController(text: e?.name ?? widget.prefillName ?? '');
    _barcodeCtrl = TextEditingController(
        text: e?.barcode ?? widget.prefillBarcode ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _quantity = e?.quantity ?? 1;
    _expiryDate = widget.scannedExpiry ?? e?.expiryDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
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
    final recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (photo == null) return;

      final input = InputImage.fromFilePath(photo.path);
      final result = await recognizer.processImage(input);
      final date = du.DateUtils.parseFromOcr(result.text);

      if (!mounted) return;
      if (date != null) {
        setState(() => _expiryDate = date);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Tarih okundu: ${DateFormat('dd.MM.yyyy').format(date)}'),
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
    }
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (code != null && mounted) {
      _barcodeCtrl.text = code;

      // 1) Once aktif urunlerde ara.
      final existing =
          await ref.read(productRepositoryProvider).findByBarcode(code);
      if (existing != null && mounted) {
        setState(() {
          _nameCtrl.text = existing.name;
          _categoryCtrl.text = existing.category ?? '';
        });
        return;
      }

      // 2) Aktif urunde bulamazsa barkod dizinine bak.
      final dirName = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .findProductName(code);
      if (dirName != null && mounted) {
        setState(() => _nameCtrl.text = dirName);
      }
    }
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

    // Barkod + ad varsa, barkod dizinine de yaz (Barkod Liste'de gorunsun).
    if (product.barcode != null && product.name.isNotEmpty) {
      await ref.read(barcodeDirectoryRepositoryProvider).importAll([
        BarcodeEntry(
          barcode: product.barcode!,
          productName: product.name,
          importedAt: DateTime.now(),
        ),
      ]);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final dateStr = _expiryDate == null
        ? 'SKT seçilmedi'
        : DateFormat('dd.MM.yyyy').format(_expiryDate!);

    // Klavye acilinca form yukari kayar (viewInsets).
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tutamac
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  isEdit ? 'Ürün Düzenle' : 'Yeni Ürün',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Ürün adı *'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Zorunlu alan'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _barcodeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Barkod',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scanBarcode,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Kategori / Reyon'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Takvimden manuel secim
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceAlt,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event,
                                  color: AppTheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Son kullanma: $dateStr',
                                    style: const TextStyle(fontSize: 15),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Fotograf cekerek tarih oku
                    Material(
                      color: AppTheme.primary.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _scanDateFromPhoto,
                        child: const Padding(
                          padding: EdgeInsets.all(18),
                          child: Icon(Icons.camera_alt_rounded,
                              color: AppTheme.primary, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildQuantitySelector(),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  child: Text(isEdit ? 'Güncelle' : 'Kaydet'),
                ),
              ],
            ),
          ),
        ),
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

/// Barkod tarama sayfasi. Tek seferlik algilama (coklu pop engellenir).
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
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
