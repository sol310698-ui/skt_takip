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
import 'image_zoom_screen.dart';
import '../widgets/ui_kit.dart';
import 'web_search_screen.dart';

/// Tam ekran urun formu (ekleme + duzenleme).
/// Tasarim: gradyanli buyuk header (gorsel + ad), govdede alanlar,
/// altta sabit aksiyon cubugu (Iptal / Kaydet).
/// Akilli: barkod -> dizin -> urunler -> Open Food Facts (isim/kategori/gorsel).
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

  Timer? _debounce;
  bool _looking = false;
  bool _saving = false;
  String? _lookupInfo;
  String? _previewImageUrl;
  String _lastLookedUp = '';

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

    final initialBarcode = _barcodeCtrl.text.trim();
    if (initialBarcode.isNotEmpty && _nameCtrl.text.trim().isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _smartLookup(initialBarcode));
    } else if (initialBarcode.isNotEmpty && widget.existing != null) {
      // Duzenlemede de gorsel cekmeyi dene (isim ezilmez).
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _smartLookup(initialBarcode));
    }
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
    _debounce = Timer(const Duration(milliseconds: 700),
        () => _smartLookup(code));
  }

  /// Kademeli arama: yerel dizin -> aktif urunler -> Open Food Facts.
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
    String? info;
    String? imageUrl;

    try {
      name = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .findProductName(code);
    } catch (_) {}

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

    // OFF: isim yoksa isim+kategori+gorsel, varsa sadece gorsel icin yine sor.
    try {
      final r = await BarcodeLookupService.instance.lookupDetailed(code);
      if (r.found) {
        imageUrl = r.imageUrl;
        if (name == null) {
          name = r.name;
          category = r.category;
          info = 'İnternetten bulundu';
        } else {
          info = 'Kayıtlardan bulundu';
        }
      } else if (name != null) {
        info = 'Kayıtlardan bulundu';
      } else {
        // Internet araması başarısız; bir sonraki girişte tekrar deneyebilsin.
        _lastLookedUp = '';
        switch (r.status) {
          case BarcodeLookupStatus.notFound:
            info = 'Bilgi bulunamadı';
            break;
          case BarcodeLookupStatus.timeout:
            info = 'İnternet yanıt vermedi';
            break;
          default:
            info = 'Bilgi alınamadı';
        }
      }
    } catch (_) {
      if (name != null) {
        info = 'Kayıtlardan bulundu';
      } else {
        _lastLookedUp = ''; // hata durumunda tekrar denemeye izin ver
      }
    }

    if (!mounted) return;
    setState(() {
      _looking = false;
      _lookupInfo = info;
      if (imageUrl != null) _previewImageUrl = imageUrl;
      if (name != null && _nameCtrl.text.trim().isEmpty) _nameCtrl.text = name;
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

  Future<void> _scanDateFromPhoto() async {
    final picker = ImagePicker();
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    List<String> variants = [];
    String? originalPath;
    try {
      final photo =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 100);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Tarih okundu: ${DateFormat('dd.MM.yyyy').format(date)}'),
          backgroundColor: AppTheme.statusSafe,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tarih okunamadı, takvimden seçebilirsiniz'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      recognizer.close();
      if (originalPath != null) {
        await ImagePreprocessService.instance.cleanup(variants, originalPath);
      }
    }
  }

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
    if (code == null || !mounted) return;
    _barcodeCtrl.text = code;

    // Mevcut aktif partileri kontrol et.
    final parties = await ref
        .read(productRepositoryProvider)
        .getAllActiveByBarcode(code);

    if (parties.isNotEmpty && mounted) {
      final addNew = await _showPartyDialog(parties);
      if (addNew == false) {
        // Ilk (en eski SKT) partiyi duzenle.
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductFormScreen(existing: parties.first),
        ));
        return;
      }
    }
    _smartLookup(code);
  }

  Future<bool?> _showPartyDialog(List<Product> parties) {
    final fmt = (DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mevcut Parti Var'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bu barkoddan ${parties.length} aktif parti:',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 10),
            ...parties.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: p.status.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${fmt(p.expiryDate)} — ${p.quantity} adet',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            const Text('Ne yapmak istersiniz?',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mevcut partiyi düzenle'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yeni parti ekle'),
          ),
        ],
      ),
    );
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
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ürün adı zorunlu')),
      );
      return;
    }
    if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen SKT seçin')),
      );
      return;
    }
    setState(() => _saving = true);

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

    try {
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          _buildHeader(isEdit),
          SliverToBoxAdapter(
            child: Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Arama durumu / resim — header kucukken buradan gorunur.
                    _buildInlinePreview(),
                    _label('Ürün Adı'),
                    TextFormField(
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        hintText: 'Ürün adı',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '' : null,
                    ),
                    const SizedBox(height: 18),
                    _label('Barkod'),
                    TextFormField(
                      controller: _barcodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Barkod numarası',
                        // Arama suruyorsa prefix spinner; bitmisse ikon.
                        // Suffix butonlari HEP aktif (kilitlenme olmaz).
                        prefixIcon: _looking
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primary),
                                ),
                              )
                            : const Icon(Icons.qr_code_rounded),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: "Google'da Ara",
                              onPressed: _searchOnline,
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Tara',
                              onPressed: _scanBarcode,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('Kategori / Reyon'),
                    TextFormField(
                      controller: _categoryCtrl,
                      decoration: const InputDecoration(
                        hintText: 'örn. Süt Ürünleri, A1 reyonu',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('Son Kullanma Tarihi'),
                    _buildExpiryCard(),
                    const SizedBox(height: 18),
                    _label('Adet'),
                    _buildQuantitySelector(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // Onemli butonlar ALTTA sabit.
      bottomNavigationBar: _buildBottomBar(isEdit),
    );
  }

  /// Header: gorsel varsa gradyanli SliverAppBar, yoksa sade AppBar yuksekligi.
  Widget _buildHeader(bool isEdit) {
    final hasImage = _previewImageUrl != null;
    return SliverAppBar(
      expandedHeight: hasImage ? 240 : kToolbarHeight,
      pinned: true,
      stretch: hasImage,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(isEdit ? 'Ürün Düzenle' : 'Yeni Ürün',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      // Gorsel yokken FlexibleSpaceBar gosterme (gri bosluk olmaz).
      flexibleSpace: hasImage
          ? FlexibleSpaceBar(
              titlePadding: EdgeInsets.zero,
              stretchModes: const [StretchMode.zoomBackground],
              background: Container(
                decoration: const BoxDecoration(
                    gradient: AppTheme.bannerGradient),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 28, bottom: 44),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeroImage(),
                          const SizedBox(height: 10),
                          if (_looking)
                            const Text('Ürün bilgisi aranıyor...',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12.5))
                          else if (_lookupInfo != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _lookupInfo!.contains('bulundu')
                                      ? Icons.check_circle_rounded
                                      : Icons.info_outline_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 5),
                                Text(_lookupInfo!,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  /// Form icindeki gorsel + durum baneri (header kucukken gorulur).
  Widget _buildInlinePreview() {
    if (!_looking && _previewImageUrl == null && _lookupInfo == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          // Gorsel (varsa)
          if (_previewImageUrl != null)
            GestureDetector(
              onTap: () => openImageZoom(context,
                  networkUrl: _previewImageUrl, heroTag: 'product_img'),
              child: Hero(
                tag: 'product_img',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                  child: CachedImage(
                    url: _previewImageUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: () => Container(
                      width: 60,
                      height: 60,
                      color: AppTheme.surfaceAlt,
                      child: const Icon(Icons.inventory_2_rounded,
                          color: AppTheme.textTertiary, size: 28),
                    ),
                  ),
                ),
              ),
            ),
          if (_previewImageUrl != null) const SizedBox(width: 14),
          // Durum
          Expanded(
            child: Row(
              children: [
                if (_looking) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _looking
                        ? 'Ürün bilgisi aranıyor...'
                        : (_lookupInfo ?? ''),
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
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return GestureDetector(
      onTap: _previewImageUrl == null
          ? null
          : () => openImageZoom(context,
              networkUrl: _previewImageUrl, heroTag: 'product_img'),
      child: Hero(
        tag: 'product_img',
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: _previewImageUrl != null
              ? CachedImage(
                  url: _previewImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: _heroPlaceholder,
                )
              : _heroPlaceholder(),
        ),
      ),
    );
  }

  Widget _heroPlaceholder() => const Icon(Icons.inventory_2_rounded,
      color: Colors.white, size: 40);

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary)),
      );

  Widget _buildExpiryCard() {
    final hasDate = _expiryDate != null;
    final dateStr = hasDate
        ? DateFormat('dd MMMM yyyy', 'tr').format(_expiryDate!)
        : 'Seçilmedi';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(accentColor: hasDate ? AppTheme.primary : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (hasDate ? AppTheme.primary : AppTheme.textTertiary)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.event_rounded,
                    color: hasDate ? AppTheme.primary : AppTheme.textTertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(dateStr,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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
                child: _miniBtn(Icons.calendar_month_rounded, 'Takvim',
                    _pickDate, false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniBtn(Icons.camera_alt_rounded, 'Foto',
                    _scanDateFromPhoto, false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniBtn(Icons.center_focus_strong_rounded, 'Hassas',
                    _preciseDate, true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(
      IconData icon, String label, VoidCallback onTap, bool filled) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: filled ? Colors.white : AppTheme.primary),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : AppTheme.primary)),
      ],
    );
    return Material(
      color: filled ? AppTheme.primary : AppTheme.primary.withOpacity(0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: child,
        ),
      ),
    );
  }

  Widget _buildQuantitySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Adet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.primary,
                onPressed:
                    _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              SizedBox(
                width: 32,
                child: Text('$_quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.primary,
                onPressed: () => setState(() => _quantity++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isEdit) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('İptal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(isEdit ? 'Güncelle' : 'Kaydet',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
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
