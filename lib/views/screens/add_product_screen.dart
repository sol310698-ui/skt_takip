import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../widgets/scan_error_retry.dart';
import '../../core/camera_lifecycle_mixin.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/camera_helper.dart';
import '../../core/services/flow_prefs.dart';
import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/image_preprocess_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/shelf_layout_service.dart';
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
  late final TextEditingController _qtyCtrl;
  late int _quantity;
  DateTime? _expiryDate;

  Timer? _debounce;
  bool _looking = false;
  bool _saving = false;
  bool _saved = false; // kayit tamamlandi -> tekrar kayit/pop garantisi
  String? _lookupInfo;
  String? _previewImageUrl;
  String? _localImagePath; // barkod dizininden yerel foto (reyon/etiket)
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
    _qtyCtrl = TextEditingController(text: '$_quantity');
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
    _qtyCtrl.dispose();
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
          case BarcodeLookupStatus.disabled:
            info = 'İnternet veri tabanı kapalı';
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

    // YEREL FOTOGRAF: barkod dizininde bu barkod icin kayitli yerel foto
    // (reyon dizilim / etiket / fiyat kontrol fotografi) varsa onizlemede
    // goster. OFF ag gorseli yoksa bile bu gorunur; varsa bile yerel
    // fotografi tercih ederiz (magazadaki gercek urun).
    try {
      final localImg = await ref
          .read(barcodeDirectoryRepositoryProvider)
          .getLocalImage(code);
      if (localImg != null &&
          localImg.isNotEmpty &&
          await File(localImg).exists()) {
        if (mounted) setState(() => _localImagePath = localImg);
      }
    } catch (_) {}

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
                        style: TextStyle(fontSize: 13),
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
    // KALICI REYON BAGI: yeni kayit + barkod reyon diziliminde varsa
    // SKT kaydi o slota baglanir (duzenlemede mevcut bag korunur).
    String? locType = base?.locationType;
    int? locRef = base?.locationRef;
    final bcTrim = _barcodeCtrl.text.trim();
    if (base == null && bcTrim.isNotEmpty) {
      try {
        final slotId =
            await ShelfLayoutService.instance.firstSlotIdByBarcode(bcTrim);
        if (slotId != null) {
          locType = 'shelf';
          locRef = slotId;
        }
      } catch (_) {}
    }
    final product = Product(
      id: base?.id,
      locationType: locType,
      locationRef: locRef,
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

  // ════════════════════════════════════════════════════════════════════
  //  YENIDEN TASARIM (v168) — "DOA" tasarim dili (PILOT, sadece bu ekran)
  // ────────────────────────────────────────────────────────────────────
  //  Referans: DOA geri-donusum uygulamasi. Acik/mint zemin, buyuk yuvarlak
  //  YESIL GRADYAN "hero" kart (DOA'daki bakiye karti gibi — burada SKT'yi
  //  one cikarir), beyaz yumusak-golgeli alan kartlari, yesil pill butonlar,
  //  havadar bosluklar. Renkler bu EKRANA OZEL yereldir (global AppTheme'e
  //  dokunulmadi) — boylece pilot digerlerini etkilemez. TUM is mantigi
  //  (OCR, arama, tarama, hizli akis, kaydetme, adet) birebir korunmustur.
  // ════════════════════════════════════════════════════════════════════

  // ── DOA paleti — TEMAYA DUYARLI ────────────────────────────────────
  //  Notr renkler (zemin/kart/metin/kenar) AppTheme'ten gelir; boylece
  //  ekran acik temada acik, KOYU temada KOYU olur ve yazilar HER ZAMAN
  //  okunur. Yesiller + hero gradyani iki temada da calistigi icin sabit.
  Color get _doaBg => AppTheme.background;
  Color get _doaBgTop => AppTheme.surface;
  Color get _doaCard => AppTheme.surface;
  Color get _doaInk => AppTheme.textPrimary;
  Color get _doaInk2 => AppTheme.textSecondary;
  Color get _doaInk3 => AppTheme.textTertiary;
  Color get _doaHair => AppTheme.hairline;
  static const Color _doaGreen = Color(0xFF23A055);   // ana yesil (iki temada)
  static const Color _doaGreenDark = Color(0xFF17843F);
  static const LinearGradient _doaHeroGrad = LinearGradient(
    colors: [Color(0xFF2BAA63), Color(0xFF178A46)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static List<BoxShadow> get _doaShadow => [
        BoxShadow(
          color: const Color(0xFF0B4F27).withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  /// Girilen tarihe gore canli durum: (renk, etiket, kalan-gun metni).
  /// Tarih yoksa null.
  ({Color color, String label, String daysText})? _liveStatus() {
    final d = _expiryDate;
    if (d == null) return null;
    final st = du.DateUtils.statusFor(d);
    final left = du.DateUtils.daysUntil(d);
    final daysText = left < 0
        ? '${-left} gün geçti'
        : left == 0
            ? 'Bugün doluyor'
            : '$left gün kaldı';
    return (color: st.color, label: st.label, daysText: daysText);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBarForColor(AppTheme.background),
      child: Scaffold(
        backgroundColor: _doaBg,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_doaBgTop, _doaBg],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _doaTopBar(isEdit),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _doaHeroCard(),
                          const SizedBox(height: 16),
                          _nameCard(),
                          const SizedBox(height: 12),
                          _barcodeCard(),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _halfField(
                                  label: 'Kategori / Reyon',
                                  hint: 'örn. Süt, A1',
                                  icon: Icons.category_outlined,
                                  controller: _categoryCtrl,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _halfField(
                                  label: 'Konum / Yer',
                                  hint: 'örn. Raf A3',
                                  icon: Icons.place_outlined,
                                  controller: _locationCtrl,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _dateCard(),
                          const SizedBox(height: 12),
                          _qtyCard(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: _doaBottomBar(isEdit),
      ),
    );
  }

  // ── UST BAR (mint zemin uzerinde geri + baslik) ────────────────────
  Widget _doaTopBar(bool isEdit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          Material(
            color: _doaCard,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.all(9),
                child: Icon(Icons.arrow_back_rounded,
                    color: _doaGreenDark, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isEdit ? 'Ürün Düzenle' : 'Yeni Ürün',
            style: TextStyle(
                color: _doaInk,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4),
          ),
        ],
      ),
    );
  }

  // ── HERO KART (DOA "bakiye" kartinin SKT karsiligi) ───────────────
  //  Urun gorseli varsa TUM karti orantili (BoxFit.cover) kaplar; ustune
  //  alttan koyu yesil okunabilirlik perdesi + SKT bilgisi biner. Gorsel
  //  yoksa yesil gradyan + imza halkalari gosterilir.
  Widget _doaHeroCard() {
    final st = _liveStatus();
    final hasDate = _expiryDate != null;
    final bigDate = hasDate
        ? DateFormat('dd MMMM yyyy', 'tr').format(_expiryDate!)
        : 'Tarih seçilmedi';
    final hasImage = _localImagePath != null || _previewImageUrl != null;
    return GestureDetector(
      onTap: hasImage ? _openHeroFullscreen : null,
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          // Gorsel varsa zemin gorsel olur (gradient yok); yoksa yesil gradyan.
          gradient: hasImage ? null : _doaHeroGrad,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: _doaGreenDark.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ARKA PLAN: urun gorseli TUM karti orantili (cover) kaplar.
              if (hasImage)
                Hero(
                  tag: 'product_img',
                  child: _localImagePath != null
                      ? Image.file(File(_localImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _heroGreenFallback())
                      : CachedImage(
                          url: _previewImageUrl!,
                          fit: BoxFit.cover,
                          placeholder: _heroGreenFallback),
                ),
              // Gorsel yoksa: DOA imza suyu (yari-seffaf beyaz halkalar).
              if (!hasImage) ...[
                Positioned(right: -46, top: -54, child: _wmCircle(180)),
                Positioned(right: 34, bottom: -66, child: _wmCircle(150)),
                Positioned(left: -34, bottom: -44, child: _wmCircle(120)),
              ],
              // OKUNABILIRLIK PERDESI: alttan koyu yesil (yazi net kalsin).
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xE6105A2E),
                    ],
                    stops: [0.0, 0.42, 1.0],
                  ),
                ),
              ),
              // TAM EKRAN IPUCU (gorsel varsa, sag ust).
              if (hasImage)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.32),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.fullscreen_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              // ICERIK: SKT bilgisi (altta).
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Son Kullanma Tarihi',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(bigDate,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6)),
                    const SizedBox(height: 12),
                    if (st != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: st.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 7),
                            Text('${st.label} · ${st.daysText}',
                                style: TextStyle(
                                    color: _doaInk,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text('Henüz seçilmedi',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wmCircle(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.08),
        ),
      );

  /// Gorsel yuklenemezse hero'da yesil gradyan zemin.
  Widget _heroGreenFallback() =>
      const DecoratedBox(decoration: BoxDecoration(gradient: _doaHeroGrad));

  void _openHeroFullscreen() {
    if (_localImagePath != null) {
      openImageZoom(context,
          filePath: _localImagePath, heroTag: 'product_img');
    } else if (_previewImageUrl != null) {
      openImageZoom(context,
          networkUrl: _previewImageUrl, heroTag: 'product_img');
    }
  }

  // ── ORTAK DOA PARCALARI ────────────────────────────────────────────
  Widget _fieldCard({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _doaCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _doaHair),
          boxShadow: _doaShadow,
        ),
        child: child,
      );

  Widget _iconBubble(IconData icon, {Color? color}) {
    final c = color ?? _doaGreen;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: c, size: 21),
    );
  }

  Widget _miniLabel(String t) => Text(t,
      style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w700, color: _doaInk2));

  InputDecoration _bareDeco(String hint) => InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
        hintText: hint,
        hintStyle: TextStyle(color: _doaInk3, fontWeight: FontWeight.w500),
      );

  // ── URUN ADI KARTI (gorsel hero'da; burada ad + arama + OCR) ───────
  Widget _nameCard() {
    final foundOk = _lookupInfo != null && _lookupInfo!.contains('bulundu');
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBubble(Icons.shopping_bag_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _miniLabel('Ürün Adı'),
                    TextFormField(
                      controller: _nameCtrl,
                      cursorColor: _doaGreen,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: _doaInk,
                          height: 1.2),
                      decoration: _bareDeco('Ürün adını yazın').copyWith(
                        suffixIcon: _nameOcrRunning
                            ? const Padding(
                                padding: EdgeInsets.all(6),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _doaGreen),
                                ),
                              )
                            : null,
                        suffixIconConstraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '' : null,
                      onChanged: (_) {
                        if (_nameOcrFailed &&
                            _nameCtrl.text.trim().isNotEmpty) {
                          setState(() => _nameOcrFailed = false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_looking ||
              _lookupInfo != null ||
              (_nameOcrFailed &&
                  _nameCtrl.text.trim().isEmpty &&
                  !_nameOcrRunning))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  if (_looking) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _doaGreen),
                    ),
                    const SizedBox(width: 8),
                    Text('Ürün bilgisi aranıyor...',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _doaInk2)),
                  ] else if (_lookupInfo != null) ...[
                    Icon(
                      foundOk
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      size: 15,
                      color: foundOk ? _doaGreen : _doaInk2,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_lookupInfo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: foundOk ? _doaGreen : _doaInk2)),
                    ),
                  ],
                  const Spacer(),
                  if (_nameOcrFailed &&
                      _nameCtrl.text.trim().isEmpty &&
                      !_nameOcrRunning)
                    GestureDetector(
                      onTap: _scanNameFromPhoto,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _doaGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.document_scanner_rounded,
                                size: 15, color: _doaGreen),
                            SizedBox(width: 5),
                            Text('Etiketten Oku',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _doaGreenDark)),
                          ],
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

  // ── BARKOD KARTI ───────────────────────────────────────────────────
  Widget _barcodeCard() {
    return _fieldCard(
      child: Row(
        children: [
          _looking
              ? Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _doaGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _doaGreen),
                    ),
                  ),
                )
              : _iconBubble(Icons.qr_code_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _miniLabel('Barkod'),
                TextFormField(
                  controller: _barcodeCtrl,
                  cursorColor: _doaGreen,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _doaInk),
                  decoration: _bareDeco('Barkod numarası'),
                ),
              ],
            ),
          ),
          _smallIconBtn(Icons.search, "Google'da Ara", _searchOnline),
          _smallIconBtn(Icons.qr_code_scanner, 'Tara', _scanBarcode),
        ],
      ),
    );
  }

  Widget _smallIconBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      IconButton(
        icon: Icon(icon, color: _doaGreen),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );

  // ── YARIM GENISLIK ALAN (Kategori / Konum) ────────────────────────
  Widget _halfField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return _fieldCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: _doaGreen),
              const SizedBox(width: 6),
              Flexible(child: _miniLabel(label)),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: controller,
            cursorColor: _doaGreen,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: _doaInk),
            decoration: _bareDeco(hint),
          ),
        ],
      ),
    );
  }

  // ── TARIH KARTI (elle giris + Takvim/Foto/Hassas) ─────────────────
  Widget _dateCard() {
    final st = _liveStatus();
    final accent = st?.color ?? _doaGreen;
    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBubble(Icons.keyboard_alt_outlined, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _miniLabel('Tarihi Elle Yaz'),
                    TextField(
                      controller: _dateTextCtrl,
                      focusNode: _dateFocus,
                      cursorColor: _doaGreen,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_DateTextInputFormatter()],
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _doaInk,
                          letterSpacing: 1.5),
                      decoration: _bareDeco('gg.aa.yyyy').copyWith(
                        hintStyle: TextStyle(
                            color: _doaInk3, letterSpacing: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _doaMethodTile(Icons.calendar_month_rounded, 'Takvim',
                    _pickDate, false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _doaMethodTile(
                    Icons.camera_alt_rounded, 'Foto', _scanDateFromPhoto, false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _doaMethodTile(Icons.center_focus_strong_rounded,
                    'Hassas', _preciseDate, true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doaMethodTile(
      IconData icon, String label, VoidCallback onTap, bool filled) {
    return Material(
      color: filled ? _doaGreen : _doaGreen.withOpacity(0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: filled ? Colors.white : _doaGreen),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : _doaGreenDark)),
            ],
          ),
        ),
      ),
    );
  }

  // ── ADET KARTI ─────────────────────────────────────────────────────
  Widget _qtyCard() {
    return _fieldCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _iconBubble(Icons.inventory_2_outlined),
          const SizedBox(width: 12),
          Text('Adet',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _doaInk)),
          const Spacer(),
          _stepBtn(
            Icons.remove_rounded,
            _quantity > 1
                ? () {
                    setState(() => _quantity--);
                    _qtyCtrl.text = '$_quantity';
                    _qtyCtrl.selection = TextSelection.collapsed(
                        offset: _qtyCtrl.text.length);
                  }
                : null,
          ),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _qtyCtrl,
              textAlign: TextAlign.center,
              cursorColor: _doaGreen,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _doaInk),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null && n >= 1) _quantity = n;
              },
              onSubmitted: (v) {
                final n = int.tryParse(v.trim());
                setState(() => _quantity = (n == null || n < 1) ? 1 : n);
                _qtyCtrl.text = '$_quantity';
              },
            ),
          ),
          _stepBtn(Icons.add_rounded, () {
            setState(() => _quantity++);
            _qtyCtrl.text = '$_quantity';
            _qtyCtrl.selection =
                TextSelection.collapsed(offset: _qtyCtrl.text.length);
          }),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? _doaGreen.withOpacity(0.12) : _doaHair,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon,
              size: 20, color: enabled ? _doaGreen : _doaInk3),
        ),
      ),
    );
  }

  // ── ALT AKSIYON CUBUGU (DOA pill butonlar) ────────────────────────
  Widget _doaBottomBar(bool isEdit) {
    return Container(
      decoration: BoxDecoration(
        color: _doaCard,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4F27).withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              // Iptal — yesil cizgili pill.
              Expanded(
                flex: 2,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap:
                        _saving ? null : () => Navigator.of(context).maybePop(),
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: _doaGreen.withOpacity(0.5), width: 1.4),
                      ),
                      child: const Text('İptal',
                          style: TextStyle(
                              color: _doaGreenDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Kaydet/Guncelle — dolu yesil pill + parlama.
              Expanded(
                flex: 3,
                child: Material(
                  color: _saving ? _doaGreen.withOpacity(0.6) : _doaGreen,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _saving ? null : _save,
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _saving
                            ? null
                            : [
                                BoxShadow(
                                  color: _doaGreenDark.withOpacity(0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_saving)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          else
                            const Icon(Icons.check_rounded,
                                color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(isEdit ? 'Güncelle' : 'Kaydet',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
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

class _BarcodeScanPageState extends State<BarcodeScanPage> with CameraLifecycleMixin {
  // Kamera yasam dongusu: arka plandan donunce kamera unlem/takilma
  // yasamasin diye durdur/yeniden baslat.
  @override
  List<MobileScannerController> get cameraControllers => [_controller];
  // Varsayilan EAN-13 (kod 13). Switch kapatilinca Code 128.
  bool _ean13 = true;
  // Tek controller, HER iki formati da okur; secili formati detect
  // asamasinda filtreleriz. Boylece switch'te kamera yeniden baslamaz
  // (yeniden kurmak kamerayi siyah birakiyordu).
  //
  // KARARLILIK: detectionSpeed = normal (noDuplicates DEGIL). Ayni barkodu
  // ust uste birden cok kez okuyup DOGRULAYABILMEK icin tekrarlar gerekli.
  // Tek karelik yanlis okuma (yansima/bulaniklik) hemen kabul edilmesin.
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.ean13, BarcodeFormat.code128],
  );
  bool _handled = false;

  // ── COK KARELI DOGRULAMA ──────────────────────────────────────────
  // Ayni barkod DEGERI pes pese [_needed] kez okununca kabul edilir.
  // Farkli bir deger okunursa sayac sifirlanir (yanlis okuma birikmez).
  static const int _needed = 3;
  String? _candidate;
  int _candidateHits = 0;

  void _toggleFormat(bool ean13) {
    setState(() {
      _ean13 = ean13;
      _handled = false;
      _candidate = null;
      _candidateHits = 0;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// EAN-13 saglama basamagi (check digit) dogrulamasi. Yanlis okunan
  /// barkodlarin buyuk cogunlugu bu testte elenir.
  bool _validEan13(String s) {
    if (s.length != 13 || int.tryParse(s) == null) return false;
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final d = s.codeUnitAt(i) - 48;
      sum += (i.isEven) ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == (s.codeUnitAt(12) - 48);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final wanted = _ean13 ? BarcodeFormat.ean13 : BarcodeFormat.code128;
    for (final b in capture.barcodes) {
      if (b.format != wanted) continue;
      final val = b.rawValue;
      if (val == null || val.isEmpty) continue;
      // EAN-13'te check-digit gecersizse bu okumayi TAMAMEN yok say.
      if (_ean13 && !_validEan13(val)) continue;

      // Ayni deger tekrar geldiyse say; degistiyse yeni adaya gec.
      if (val == _candidate) {
        _candidateHits++;
      } else {
        _candidate = val;
        _candidateHits = 1;
      }

      // Yeterli tekrar birikince kabul et.
      if (_candidateHits >= _needed) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(val);
      }
      return; // her capture'da tek aday isle
    }
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
                  style: TextStyle(
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
            errorBuilder: (context, error) =>
                ScanErrorRetry(controller: _controller),
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
              style: TextStyle(color: Colors.white, fontSize: 15),
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
