import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/camera_helper.dart';
import '../../core/services/flow_prefs.dart';
import '../../core/services/gemini_ocr_service.dart';
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
  /// SKT tarama akisinda Gemini AI ile cekilmis etiket fotografinin yolu
  /// (varsa). Barkod aramasi urun adini bulamazsa, bu fotograf isim OCR'i
  /// icin otomatik kullanilir.
  final String? labelPhotoPath;

  const ProductFormScreen({
    super.key,
    this.existing,
    this.scannedExpiry,
    this.prefillBarcode,
    this.prefillName,
    this.labelPhotoPath,
  });

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _locationCtrl;
  // Elle hizli tarih girisi icin (gg.aa.yyyy). Numerik klavye + oto nokta.
  late final TextEditingController _dateTextCtrl;
  late int _quantity;
  DateTime? _expiryDate;

  Timer? _debounce;
  bool _looking = false;
  bool _saving = false;
  bool _saved = false; // kayit tamamlandi -> tekrar kayit/pop garantisi
  String? _lookupInfo;
  String? _previewImageUrl;
  String _lastLookedUp = '';

  // Hizli manuel akis: ekran acilinca tarih kutusuna odaklan, tarih
  // girilince otomatik barkod taramaya gec, barkod taraninca oto kaydet.
  final FocusNode _dateFocus = FocusNode();
  bool _fastManual = false;
  bool _fastBarcodeStarted = false; // tarih sonrasi tek sefer tetikle
  bool _autoSaveTriggered = false; // hizli akista oto-kaydet tek sefer

  // URUN ADI OCR (etiketten otomatik/elle okuma).
  // Barkod aramasi isim bulamazsa: once elimizdeki etiket fotografiyla
  // (varsa) sessizce dene; bulamazsa "Etiketten Oku" butonu goster.
  bool _nameOcrTried = false; // ayni foto ile tekrar tekrar denemeyi onler
  bool _nameOcrRunning = false;
  bool _nameOcrFailed = false; // buton gosterimi icin

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl =
        TextEditingController(text: e?.name ?? widget.prefillName ?? '');
    _barcodeCtrl =
        TextEditingController(text: e?.barcode ?? widget.prefillBarcode ?? '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _quantity = e?.quantity ?? 1;
    _expiryDate = widget.scannedExpiry ?? e?.expiryDate;
    // Mevcut tarih varsa metin kutusunu da doldur (gg.aa.yyyy).
    _dateTextCtrl = TextEditingController(
      text: _expiryDate != null
          ? DateFormat('dd.MM.yyyy').format(_expiryDate!)
          : '',
    );
    _dateTextCtrl.addListener(_onDateTextChanged);

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

    // HIZLI AKIS (yeni urun, duzenleme degil). Yeni siralama: ÖNCE barkod
    // tarandi (home_screen'de), SONRA SKT tarama ekranina gecildi; ikisi de
    // burada widget parametreleri olarak hazir gelir.
    _fastManual = FlowPrefs.instance.fastFlow && widget.existing == null;
    if (_fastManual) {
      if (initialBarcode.isNotEmpty && widget.scannedExpiry != null) {
        // Barkod + SKT ikisi de hazir: tekrar tarama EKRANINA gitme,
        // dogrudan isim/kategori aranip (_smartLookup zaten yukarida
        // tetiklendi) bulununca otomatik kaydet. _scanBarcode'a GEREK YOK
        // (mukerrer barkod tarama ekrani acilmasin).
        _fastBarcodeStarted = true;
      } else if (widget.scannedExpiry != null && initialBarcode.isEmpty) {
        // SKT var ama barkod yok (kullanici barkod taramayi atladi):
        // barkod taramaya gec.
        _fastBarcodeStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanBarcode();
        });
      } else if (widget.scannedExpiry == null) {
        // Tarih yok: tarih kutusuna odaklan (klavye dogrudan acilir).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _dateFocus.requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _barcodeCtrl.removeListener(_onBarcodeChanged);
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _categoryCtrl.dispose();
    _locationCtrl.dispose();
    _dateTextCtrl.removeListener(_onDateTextChanged);
    _dateTextCtrl.dispose();
    _dateFocus.dispose();
    super.dispose();
  }

  /// Elle yazilan tarih metnini (gg.aa.yyyy) grecerli bir tarihe cevirir.
  /// 8 hane (gg+aa+yyyy) tamamlaninca ve gercekten gecerli bir tarihse
  /// _expiryDate'i gunceller. Eksik/gecersizse _expiryDate'e dokunmaz
  /// (kullanici yazmaya devam ediyor olabilir).
  void _onDateTextChanged() {
    final digits = _dateTextCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Esnek ayristirici: gg.aa.yyyy, gg.aa.yy, aa.yy (ay/yil) hepsini cozer.
    final candidate = du.DateUtils.parseManual(_dateTextCtrl.text);
    if (candidate != null && _expiryDate != candidate) {
      setState(() => _expiryDate = candidate);
    }
    // Hizli manuel akis: kullanici YETERINCE yazinca (en az 6 hane =
    // gg.aa.yy, ya da 4 hane ay/yil) ve gecerli tarih olunca otomatik
    // barkod taramaya gec. Erken (2-3 hane) tetiklemeyiz ki kullanici
    // yazmayi bitirsin.
    if (_fastManual &&
        !_fastBarcodeStarted &&
        candidate != null &&
        digits.length >= 4) {
      _fastBarcodeStarted = true;
      _dateFocus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanBarcode();
      });
    }
  }

  /// Takvim/Foto/Hassas ile tarih secildiginde metin kutusunu da senkronla.
  void _syncDateText() {
    final newText = _expiryDate != null
        ? DateFormat('dd.MM.yyyy').format(_expiryDate!)
        : '';
    if (_dateTextCtrl.text != newText) {
      _dateTextCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
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

    // HIZLI MANUEL AKIS: barkod tarandi + tarih zaten var. Isim de bulunduysa
    // otomatik kaydet. TEK SEFER tetiklenir (_autoSaveTriggered), boylece
    // _smartLookup birden cok kez calissa bile mukerrer kayit olmaz.
    if (_fastManual &&
        _fastBarcodeStarted &&
        !_autoSaveTriggered &&
        !_saving &&
        !_saved) {
      final hasName = _nameCtrl.text.trim().isNotEmpty;
      final hasDate = _expiryDate != null;
      if (hasName && hasDate) {
        _autoSaveTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_saving && !_saved) _save();
        });
      } else if (!hasName) {
        // ISIM BULUNAMADI: once etiket fotografi varsa sessizce OCR dene.
        // Foto yoksa veya OCR de basarisiz olursa kullaniciya "Etiketten
        // Oku" butonu gosterilir (bkz. _tryAutoNameOcr).
        await _tryAutoNameOcr();
      }
    } else if (_nameCtrl.text.trim().isEmpty) {
      // Hizli akis disinda da (manuel duzenleme/normal akis) isim
      // bulunamadiysa ayni otomatik deneme + buton mantigi gecerli olsun.
      await _tryAutoNameOcr();
    }
  }

  /// ISIM OCR — ONCE OTOMATIK DENE, BULAMAZSA BUTON GOSTER.
  /// SKT tarama akisindan gelen etiket fotografi (widget.labelPhotoPath)
  /// varsa, kullaniciya hic sormadan sessizce Gemini'ye gonderip urun
  /// adini cikarmayi dener. Basarili olursa _nameCtrl otomatik doldurulur.
  /// Foto yoksa, anahtar yoksa veya okuma basarisiz olursa sessizce
  /// _nameOcrFailed=true yapilir; bu da formda "Etiketten Oku" butonunun
  /// gorunmesini saglar (kullanici elle fotograf cekip deneyebilir).
  Future<void> _tryAutoNameOcr() async {
    if (_nameOcrTried) return; // ayni foto ile tekrar tekrar denenmesin
    if (_nameCtrl.text.trim().isNotEmpty) return; // bu arada isim geldi
    final path = widget.labelPhotoPath;
    if (path == null || path.isEmpty) {
      // Otomatik denenecek foto yok: direkt buton gosterimine gec.
      if (mounted) setState(() => _nameOcrFailed = true);
      return;
    }
    _nameOcrTried = true;
    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      // Gecici dosya artik yoksa (sistem temizlemis olabilir) sessizce
      // butona dus.
      if (mounted) setState(() => _nameOcrFailed = true);
      return;
    }
    final hasKey = await GeminiOcrService.instance.hasApiKey();
    if (!hasKey) {
      if (mounted) setState(() => _nameOcrFailed = true);
      return;
    }
    if (mounted) setState(() => _nameOcrRunning = true);
    try {
      final name =
          await GeminiOcrService.instance.extractProductName(file);
      if (!mounted) return;
      setState(() {
        _nameOcrRunning = false;
        if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = name;
      });
      // Isim simdi geldi: hizli akista otomatik kaydet zincirini tekrar
      // tetikle (tarih de hazirsa kaydedilir).
      if (_fastManual &&
          _fastBarcodeStarted &&
          !_autoSaveTriggered &&
          !_saving &&
          !_saved &&
          _expiryDate != null) {
        _autoSaveTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_saving && !_saved) _save();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nameOcrRunning = false;
        _nameOcrFailed = true;
      });
    }
  }

  /// "Etiketten Oku" butonu: kullanici elle fotograf cekip urun adini
  /// OCR ile doldurmayi tekrar dener (otomatik deneme basarisiz olduysa
  /// veya hic etiket fotografi yoksa kullanilir).
  Future<void> _scanNameFromPhoto() async {
    final hasKey = await GeminiOcrService.instance.hasApiKey();
    if (!hasKey) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Gemini API anahtarı tanımlı değil. Ayarlardan ekleyin veya '
              'ürün adını elle girin.'),
        ));
      }
      return;
    }
    final photo = await CameraHelper.pickImage(
        source: ImageSource.camera, imageQuality: 100);
    if (photo == null || !mounted) return;
    setState(() => _nameOcrRunning = true);
    try {
      final name = await GeminiOcrService.instance
          .extractProductName(File(photo.path));
      if (!mounted) return;
      setState(() {
        _nameOcrRunning = false;
        _nameOcrFailed = false;
        _nameCtrl.text = name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _nameOcrRunning = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ürün adı okunamadı: $e'),
      ));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() => _expiryDate = picked);
      _syncDateText();
    }
  }

  Future<void> _scanDateFromPhoto() async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    List<String> variants = [];
    String? originalPath;
    try {
      final photo = await CameraHelper.pickImage(
          source: ImageSource.camera, imageQuality: 100);
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
        _syncDateText();
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
      _syncDateText();
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
                style: TextStyle(
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
    // MUKERRER KAYIT KORUMASI: zaten kaydediliyor veya kaydedildiyse cik.
    // (Hizli akista otomatik + kullanicinin elle basmasi ust uste gelebilir.)
    if (_saving || _saved) return;

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
      location: _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim(),
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
        // Kullanici urunu ELLE ekledi -> girdigi isim en dogru/guncel tanim.
        // forceOverwrite: true ile, barkod rehberinde mevcut kayit (Excel
        // dahil) varsa bile urun adi bunun uzerine yazilir.
        await ref.read(barcodeDirectoryRepositoryProvider).importAll(
          [
            BarcodeEntry(
              barcode: product.barcode!,
              productName: product.name,
              importedAt: DateTime.now(),
              source: BarcodeSource.manual,
            ),
          ],
          forceOverwrite: true,
        );
      }
      // Kayit tamamlandi: bayragi isaretle (tekrar kayit engellenir) ve
      // ekrani kapat -> cagiran ekran (SKT Tara) otomatik geri doner.
      _saved = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Hata olursa kullanici tekrar deneyebilsin diye bayraklari sifirla.
      _saved = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted && !_saved) setState(() => _saving = false);
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
                      decoration: InputDecoration(
                        hintText: 'Ürün adı',
                        prefixIcon: const Icon(Icons.shopping_bag_outlined),
                        suffixIcon: _nameOcrRunning
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.accent),
                                ),
                              )
                            : null,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '' : null,
                      onChanged: (_) {
                        // Kullanici elle yazmaya basladiysa OCR basarisizlik
                        // butonunu gizle (artik gerek yok).
                        if (_nameOcrFailed && _nameCtrl.text.trim().isNotEmpty) {
                          setState(() => _nameOcrFailed = false);
                        }
                      },
                    ),
                    // ETIKETTEN OKU: isim bos + otomatik OCR de basarisiz
                    // olduysa (veya hic etiket fotografi yoksa) bu buton
                    // gorunur; kullanici elle fotograf cekip deneyebilir.
                    if (_nameOcrFailed &&
                        _nameCtrl.text.trim().isEmpty &&
                        !_nameOcrRunning)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _scanNameFromPhoto,
                            icon: const Icon(Icons.document_scanner_rounded,
                                size: 18),
                            label: const Text('Etiketten Oku'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.accent),
                          ),
                        ),
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
                    _label('Konum / Yer'),
                    TextFormField(
                      controller: _locationCtrl,
                      decoration: const InputDecoration(
                        hintText: 'örn. Raf A3, Zemin, B Koridoru Sağ',
                        prefixIcon: Icon(Icons.place_outlined),
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
      systemOverlayStyle: AppTheme.systemBarForColor(AppTheme.primary),
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

  /// Form icindeki arama durumu baneri (gorsel YOK; gorsel ustteki header'da).
  Widget _buildInlinePreview() {
    if (!_looking && _lookupInfo == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              _lookupInfo != null && _lookupInfo!.contains('bulundu')
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              size: 16,
              color: _lookupInfo != null && _lookupInfo!.contains('bulundu')
                  ? AppTheme.statusSafe
                  : AppTheme.textSecondary,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _looking ? 'Ürün bilgisi aranıyor...' : (_lookupInfo ?? ''),
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
            style: TextStyle(
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
          // Elle hizli tarih girisi: numerik klavye, otomatik nokta (gg.aa.yyyy).
          TextField(
            controller: _dateTextCtrl,
            focusNode: _dateFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [_DateTextInputFormatter()],
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: 1.5),
            decoration: InputDecoration(
              hintText: 'gg.aa.yyyy',
              hintStyle: TextStyle(
                  color: AppTheme.textTertiary, letterSpacing: 1.5),
              prefixIcon: Icon(Icons.keyboard_rounded,
                  color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.background.withOpacity(0.4),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
  // Varsayilan EAN-13 (kod 13). Switch kapatilinca Code 128.
  bool _ean13 = true;
  late MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  MobileScannerController _buildController() {
    return MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: _ean13
          ? const [BarcodeFormat.ean13]
          : const [BarcodeFormat.code128],
    );
  }

  Future<void> _toggleFormat(bool ean13) async {
    setState(() => _ean13 = ean13);
    _handled = false;
    // mobile_scanner v5: format degisimi icin controller'i yeniden kur.
    final old = _controller;
    _controller = _buildController();
    await old.dispose();
    if (mounted) setState(() {});
    await _controller.start();
  }

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
      backgroundColor: Colors.black,
      // Kamera onizlemesi status bar arkasina kadar uzansin.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Barkod Tara'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        actions: [
          // EAN-13 / Code 128 secimi. Acik = EAN-13 (varsayilan).
          Row(
            children: [
              Text(_ean13 ? 'EAN-13' : 'Code 128',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Switch(
                value: _ean13,
                onChanged: _toggleFormat,
              ),
            ],
          ),
        ],
      ),
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
          Positioned(
            bottom: 60,
            child: Text(
              _ean13
                  ? 'Barkodu çerçeveye getirin (EAN-13)'
                  : 'Barkodu çerçeveye getirin (Code 128)',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

/// gg.aa.yyyy formatinda otomatik nokta ekleyen tarih input formatter'i.
/// Kullanici sadece rakam yazar; 2. ve 4. rakamdan sonra otomatik "." gelir.
/// En fazla 8 rakam (gun+ay+yil) kabul eder.
class _DateTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      if (i == 2 || i == 4) buf.write('.');
      buf.write(trimmed[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
