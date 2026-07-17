import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/label_pending_queue_service.dart';
import '../../core/services/flow_prefs.dart';
import '../../core/services/pending_products_queue.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/services/database_service.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../widgets/scan_overlay.dart';
import 'label_print_screen.dart';
import 'pending_products_screen.dart';
import 'quick_photo_capture_screen.dart';

/// ════════════════════════════════════════════════════════════════════
///  FIYAT KONTROL ASISTANI
/// ────────────────────────────────────────────────────────────────────
///  Gorme dostu: reyondaki urunun ETIKET fiyati (QR) ile sirket
///  sistemindeki "Sistem Fiyati" (erisilebilirlik servisi okur)
///  karsilastirilir. Uyusmazlik varsa sesli + titresimli uyari.
///
///  Akis:
///   1) Sirket uygulamasinda barkodu okut -> ekranda "Sistem Fiyati" cikar.
///      (Erisilebilirlik servisi arka planda bu degeri yakalar.)
///   2) Bu ekrana gec, etiketin QR'ini okut.
///      QR format: barkod*fiyat*degisimTarihi*etiketTarihi saat
///   3) Sonuc aninda sesli okunur, uyusmazlik varsa titresir.
/// ════════════════════════════════════════════════════════════════════
class PriceCheckScreen extends StatefulWidget {
  const PriceCheckScreen({super.key});

  @override
  State<PriceCheckScreen> createState() => _PriceCheckScreenState();
}

class _PriceCheckScreenState extends State<PriceCheckScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.all],
    autoStart: false,
  );

  bool _scanning = false;
  bool _busy = false;
  bool _serviceOn = false;
  // OTOMATIK GEZINME anahtari (sag ustteki switch). Kalici (FlowPrefs).
  bool _autoFlow = false;

  // Servis acik/kapali durumunu periyodik kontrol eden zamanlayici.
  // (Eskiden burada gorunur bir "TANI PANELI" de besleniyordu; kullanici
  // istegiyle o panel KALDIRILDI — bu zamanlayici artik SADECE _serviceOn
  // bayragini güncellemek icin var, ekranda hicbir gorunur cikti uretmez.)
  Timer? _serviceStatusTimer;
  StreamSubscription<SystemPriceSnapshot>? _liveSub; // canli sistem verisi
  Timer? _autoRescanTimer; // sonuc sonrasi otomatik yeniden tarama

  // Ortak yerel veritabani (barkod dizini) — urun fotografini buraya yazariz.
  final BarcodeDirectoryDataSource _barcodeDs =
      BarcodeDirectoryDataSource(DatabaseService.instance);

  // Bu oturumda foto teklifi yapilan/iptal edilen barkodlar — ayni urun icin
  // pes pese tekrar tekrar sormamak icin. (Basarili kayittan sonra zaten
  // yerel foto olustugu icin bir daha sorulmaz.)
  final Set<String> _photoHandled = <String>{};

  // ── REYON KAYDI MODU ──
  // Acikken, fiyat kontrol edilen her urun ayni anda secili reyon hucresine
  // (sutun/raf) eklenir; boylece fiyat kontrolu yaparken planogram da olusur.
  // Ikinci kez dolasmaya gerek kalmaz.
  bool _reyonMode = false;
  ShelfUnit? _reyonUnit;
  int _reyonSection = 1;
  int _reyonRow = 1;
  // En son cekilen fotografin yolu — reyon slotunda yeniden kullanilir
  // (ayni urun icin iki kez foto cektirmemek icin).
  String? _lastPhotoPath;

  // ── CANLI sistem verisi (erisilebilirlik servisinden surekli okunur) ──
  // QR okutmadan, sirket uygulamasinda urun degistikce guncellenir.
  double? _livePrice;
  String? _liveProductName;
  String? _liveBarcode;
  String? _liveStockCode;

  // Son sonuc
  String? _labelBarcode;
  double? _labelPrice;
  double? _systemPrice;
  String? _systemBarcode;
  String? _systemStockCode; // sonuc anindaki sistem stok kodu (etiket basimi icin)
  String? _systemProductName;
  _CompareResult? _result;

  @override
  void initState() {
    super.initState();
    // v2: Sirket uygulamasina gecip GERI DONUS anini yakalamak icin
    // gerekli. Eskiden bu ekran uygulama yasam dongusunu hic dinlemiyordu;
    // bu yuzden donus anindaki kamera/erisilebilirlik durumu ELE
    // ALINMIYORDU — kamera bazi cihazlarda arka plandan donerken
    // bos/dondurulmus bir kare ile kalabiliyor, bu da "ekrana gelince
    // taramiyor/gec basliyor" hissini guclendiriyordu. didChangeAppLifecycle
    // State asagida bu durumu duzeltir.
    WidgetsBinding.instance.addObserver(this);
    _init();

    // OTOMATIK GEZINME tercihini yukle ve native tarafa bildir.
    _autoFlow = FlowPrefs.instance.autoFlow;
    PriceCheckChannel.setAutoFlow(_autoFlow);
    // Servis acik/kapali durumunu her saniye kontrol et (sadece uyari
    // satirinin gosterilip gosterilmeyecegine karar vermek icin).
    _serviceStatusTimer =
        Timer.periodic(const Duration(seconds: 1), (_) async {
      final info = await PriceCheckChannel.getDebugInfo();
      if (mounted && info.containsKey('running')) {
        final running = info['running'] == true;
        if (running != _serviceOn) {
          setState(() => _serviceOn = running);
        }
      }
    });

    // ── CANLI sistem verisi: artik PUSH (stream), POLLING DEGIL ──
    // Eskiden burada 600ms'lik Timer.periodic ile native SORGULANIYORDU.
    // "Sirket uygulamasindan geri donunce fiyati gec okuyor" sikayetinin
    // birebir sebebi buydu: gercek okuma ile bu Timer'in bir sonraki
    // tick'i arasinda gecen sure kayipti. Artik PriceAccessibilityService
    // deger DEGISTIGI ANDA bu stream'e basar; biz sadece dinleriz. Ekran
    // acildigi an native taraf zaten bilinen son durumu hemen gonderir
    // (bkz. MainActivity onListen), bu yuzden ilk kare de BOS kalmaz.
    _liveSub = PriceCheckChannel.systemPriceStream.listen((sys) {
      if (!mounted) return;
      final changed = sys.price != _livePrice ||
          sys.barcode != _liveBarcode ||
          sys.productName != _liveProductName;
      if (!changed) return;
      setState(() {
        _livePrice = sys.price;
        _liveProductName = sys.productName;
        _liveBarcode = sys.barcode;
        _liveStockCode = sys.stockCode;
      });
    });
  }

  Future<void> _init() async {
    final on = await PriceCheckChannel.isServiceRunning();
    if (!mounted) return;
    setState(() => _serviceOn = on);

    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted || status.isLimited) {
      await _controller.start();
      if (mounted) setState(() => _scanning = true);
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Kamera izni gerekli. Lutfen uygulama ayarlarindan izin verin.'),
          action: SnackBarAction(label: 'Ayarlar', onPressed: openAppSettings),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Ekrandan cikinca otomatik gezinmeyi native tarafta da durdur; arka
    // planda beklenmedik uygulama gecisleri olmasin.
    PriceCheckChannel.setAutoFlow(false);
    _serviceStatusTimer?.cancel();
    _liveSub?.cancel();
    _autoRescanTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // v2: Sirket uygulamasindan GERI DONUS anini burada yakaliyoruz.
    // Once: mobile_scanner'in kamera kaynagini OS'un arka planda geri
    // alip almadigindan BAGIMSIZ olarak, taramayi guvenle yeniden
    // baslatiyoruz (zaten calisiyorsa MobileScannerController bunu
    // sessizce yutar). Sonra: native erisilebilirlik tarafinin da ayni
    // resume olayini gormus olmasini beklemeden, kendi tarafimizdan
    // "tani panelini hemen tazele" tetikliyoruz — boylece kullanici
    // "Servis acik mi" / canli kart bilgisinin bayatlamadigini gorur.
    // (Asil fiyat verisi zaten push/stream ile geldigi icin burada
    // ekstra bir sorgu YAPMIYORUZ; sadece kamerayi ve tani panelini
    // tazeliyoruz.)
    if (state == AppLifecycleState.resumed) {
      if (_scanning && !_busy) {
        _controller.start();
      }
      _refreshServiceStatus();
      // OTOMATIK GEZINME: sirket uygulamasi yeni urun gosterince native bizi
      // one getirdi. Kullanici elle bir sey yapmadan raf etiketini
      // okutabilsin diye TAZE bir tarama baslat (onceki sonucu temizleyip
      // tarayiciyi ac). Bir sonuc gosteriliyorsa ya da tarama zaten
      // calisiyorsa dokunma.
      if (_autoFlow && !_busy && (_result != null || !_scanning)) {
        _autoRescanTimer?.cancel();
        _scanAgain(clearSystem: false);
      }
    }
  }

  // QR ham metnini parse et.
  // Once "barkod*fiyat*..." formati denenir. Tutmazsa, metindeki ILK
  // fiyat formatli sayi (9,95 / 9.95) fiyat olarak alinir; barkod varsa
  // ilk uzun rakam dizisi barkod sayilir. Boylece farkli etiket QR
  // formatlari da calisir.
  ({String barcode, double price})? _parseLabelQr(String raw) {
    // 1) Yildizli format
    final parts = raw.split('*');
    if (parts.length >= 2) {
      final barcode = parts[0].trim();
      final priceStr = parts[1].trim().replaceAll(',', '.');
      final price = double.tryParse(priceStr);
      if (price != null &&
          barcode.isNotEmpty &&
          RegExp(r'^\d+$').hasMatch(barcode)) {
        return (barcode: barcode, price: price);
      }
    }

    // 2) Esnek: metindeki ilk fiyat (ondalikli sayi) + ilk uzun rakam dizisi
    final priceMatch =
        RegExp(r'(\d{1,6}[.,]\d{1,2})').firstMatch(raw);
    if (priceMatch != null) {
      final price = double.tryParse(
          priceMatch.group(1)!.replaceAll(',', '.'));
      if (price != null) {
        final bcMatch = RegExp(r'\d{8,13}').firstMatch(raw);
        return (barcode: bcMatch?.group(0) ?? '—', price: price);
      }
    }
    return null;
  }

  /// "Denetim Formu" / sube-magaza adi gibi sabit, urune ozel OLMAYAN
  /// basliklarin kuyruga yanlislikla urun adi olarak eklenmesini engelleyen
  /// son kontrol katmani. Native taraftaki ayni adli mantigin (bkz.
  /// PriceAccessibilityService.isLikelyStaticFormLabel) Flutter tarafindaki
  /// karsiligidir — iki bagimsiz katmanda kontrol, tek noktada olabilecek
  /// bir gozden kacirmaya karsi savunma saglar.
  bool _looksLikeStaticFormLabel(String line) {
    final normalized = line.trim();
    final lower = normalized.toLowerCase();
    const staticPhrases = [
      'denetim formu',
      'kontrol formu',
      'fiyat kontrol',
      'fiyat kontrolü',
      'ürün denetim',
      'urun denetim',
    ];
    if (staticPhrases.any((p) => lower == p || lower.startsWith('$p '))) {
      return true;
    }
    final upper = normalized.toUpperCase();
    const storeKeywords = [
      'AVM',
      'MAĞAZA',
      'MAGAZA',
      'ŞUBE',
      'SUBE',
      'STORE',
      'PLAZA',
    ];
    return storeKeywords.any((k) => upper.contains(k));
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final parsed = _parseLabelQr(raw);
    if (parsed == null) {
      // QR okundu AMA fiyat cikarilamadi. Tani paneli kaldirildigi icin
      // (kullanici istegiyle) bu durumu kisa bir SnackBar ile bildiriyoruz;
      // sessizce yutmak kullaniciyi "hicbir sey olmuyor" hissiyle bas basa
      // birakirdi.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR okundu ama fiyat bulunamadı, tekrar deneyin'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _scanning = false;
    });
    await _controller.stop();

    // Sistem verisini native erisilebilirlik servisinden cek (fiyat +
    // barkod + stok kodu + urun adi).
    final sys = await PriceCheckChannel.getLastSystemPrice();
    final systemPrice = sys.price;
    final systemBarcode = sys.barcode;

    final result = _compare(
      labelPrice: parsed.price,
      labelBarcode: parsed.barcode,
      systemPrice: systemPrice,
      systemBarcode: systemBarcode,
    );

    // Sistemde gecerli urun bilgisi varsa, onay kuyruguna ekle (DB'ye
    // dogrudan YAZMAZ; kullanici onay sayfasinda kaydedecek). Yanlis etiket
    // olsa bile sistem urunu dogru oldugundan kuyruga sistem barkodu yazilir.
    //
    // v2 — EK GUVENLIK KATMANI: Native taraf (PriceAccessibilityService)
    // zaten "Denetim Formu" / sube-magaza adi gibi sabit form basliklarini
    // urun adi olarak SECMEMELI (konumsal + anahtar kelime filtresiyle
    // engellendi). Ama iki bagimsiz katmanda da kontrol etmek (defense in
    // depth) tek bir noktada olabilecek bir gozden kacirmayi tolere eder.
    // Bu yuzden Flutter tarafinda da ayni sabit-etiket kontrolu tekrarlanir
    // — boylece "Denetim Formu" gibi bir deger HER NE OLURSA OLSUN kuyruga
    // bir urun gibi eklenemez.
    final candidateName = sys.productName?.trim();
    if (systemBarcode != null &&
        candidateName != null &&
        candidateName.isNotEmpty &&
        !_looksLikeStaticFormLabel(candidateName)) {
      addPendingProduct(PendingProduct(
        barcode: systemBarcode,
        stockCode: sys.stockCode,
        productName: candidateName,
        systemPrice: systemPrice,
        scannedAt: DateTime.now(),
      ));
    }

    if (!mounted) return;
    setState(() {
      _labelBarcode = parsed.barcode;
      _labelPrice = parsed.price;
      _systemPrice = systemPrice;
      _systemBarcode = systemBarcode;
      _systemStockCode = sys.stockCode;
      _systemProductName = sys.productName;
      _result = result;
      _busy = false;
    });

    // Sesli + titresimli geri bildirim.
    await _announce(result, parsed.price, systemPrice);

    // ── HATALI SONUC -> ETIKET BASIMINA GONDER TEKLIFI ──
    // Yanlis etiket / yanlis fiyat durumunda raftaki etiketin YENIDEN
    // BASILMASI gerekir. Kullaniciyi ayri bir ekrana gitmeye zorlamak
    // yerine, sonucun hemen ardindan kayan bir pencere acilir ve urun tek
    // dokunusla Etiket Basim listelerinden birine gonderilebilir.
    //
    // Bu sirada OTOMATIK YENIDEN TARAMA CALISMAZ (pencere aciktir);
    // pencere kapaninca tarama kaldigi yerden devam eder.
    if (_needsNewLabel(result)) {
      _autoRescanTimer?.cancel();
      await _offerLabelPrint(result);
      if (!mounted) return;
      // Etiket teklifinden sonra, sistem urununun fotosu yoksa cek.
      final photographed = await _maybeCaptureProductPhoto();
      if (!mounted) return;
      await _maybeAddToReyon(); // reyon modu aciksa hucreye ekle
      if (!mounted) return;
      if (_autoFlow) {
        // Foto cekildiyse HEMEN sirket uygulamasina don (bekleme yok).
        _returnToCompanyApp(immediate: photographed);
      } else {
        await _scanAgain();
      }
      return;
    }

    // Sonuc dogru/uyumlu: once foto eksikse cek.
    final photographed = await _maybeCaptureProductPhoto();
    if (!mounted) return;
    await _maybeAddToReyon(); // reyon modu aciksa hucreye ekle
    if (!mounted) return;

    if (_autoFlow) {
      // OTOMATIK GEZINME: foto cekildiyse HEMEN don; cekilmediyse sonucu
      // duymak/gormek icin cok kisa bir bekleme sonrasi don.
      _returnToCompanyApp(immediate: photographed);
    } else {
      // OTOMATIK DEVAM (yerinde): kullanici "Tekrar Okut"a basmasin.
      _scheduleAutoRescan();
    }
  }

  /// Sag ustteki anahtar: otomatik gezinmeyi ac/kapat. Hem kalici tercihe
  /// yazar hem native tarafa bildirir. Kapatilirsa bekleyen donus/tarama
  /// zamanlayicisini iptal eder.
  Future<void> _setAutoFlow(bool value) async {
    setState(() => _autoFlow = value);
    await FlowPrefs.instance.setAutoFlow(value);
    await PriceCheckChannel.setAutoFlow(value);
    if (!value) {
      _autoRescanTimer?.cancel();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(value
              ? 'Otomatik gezinme açık: ürün okununca uygulama kendiliğinden gelir'
              : 'Otomatik gezinme kapalı'),
        ),
      );
    }
  }

  /// Auto-flow: sirket uygulamasina geri doner.
  ///  - [immediate] true ise (orn. foto cekildikten sonra) HIC BEKLEMEDEN.
  ///  - Aksi halde sonucu duymak/gormek icin cok kisa bir gecikme (900 ms).
  /// Native taraf, sirket uygulamasi bir sonraki urunu gosterince bizi
  /// otomatik tekrar one getirir.
  void _returnToCompanyApp({bool immediate = false}) {
    _autoRescanTimer?.cancel();
    if (immediate) {
      PriceCheckChannel.switchToCompanyApp();
      return;
    }
    _autoRescanTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _result != null && !_scanning && !_busy) {
        PriceCheckChannel.switchToCompanyApp();
      }
    });
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  URUN FOTOGRAFI EKSIKSE — UYGULAMA ICINDE CEK, ORTAK DB'YE KAYDET
  /// ──────────────────────────────────────────────────────────────────
  ///  Kural: Sistemdeki urunun (systemBarcode) ortak yerel veritabaninda
  ///  (barkod dizini) fotografi YOKSA, uygulama ICINDE hizli cekim ekrani
  ///  acilir (telefonun kamera uygulamasi ACILMAZ — pil/hiz kaybi olmaz).
  ///  Cekilen foto 720 px'e kucultulup barkod dizinine yazilir; boylece
  ///  uygulamanin HER YERINDE ve internet olmadan da gorunur.
  ///
  ///  Sadece gecerli bir sistem urunu (barkod + ad) oldugunda calisir; ayni
  ///  urun icin oturumda bir kez sorulur.
  /// ══════════════════════════════════════════════════════════════════
  /// Sistem urununun yerel fotosu yoksa uygulama ici cekim acar.
  /// Foto CEKILIP kaydedildiyse `true`, aksi halde `false` doner (cagiran
  /// taraf foto cekildiyse sirket uygulamasina HEMEN donebilsin diye).
  Future<bool> _maybeCaptureProductPhoto() async {
    _lastPhotoPath = null;
    final barcode = _systemBarcode?.trim();
    final name = _systemProductName?.trim();
    if (barcode == null || barcode.isEmpty) return false;
    if (name == null || name.isEmpty || _looksLikeStaticFormLabel(name)) return false;

    // Zaten yerel foto var mi? Varsa REYON kaydinda yeniden kullanmak icin
    // yolunu tut; ama yeni foto icin tekrar sorma.
    String? existing;
    try {
      existing = await _barcodeDs.getLocalImage(barcode);
    } catch (_) {
      existing = null;
    }
    if (existing != null && existing.isNotEmpty && File(existing).existsSync()) {
      _lastPhotoPath = existing;
      _photoHandled.add(barcode);
      return false;
    }

    if (_photoHandled.contains(barcode)) return false;
    if (!mounted) return false;
    _autoRescanTimer?.cancel();
    _photoHandled.add(barcode); // iptal edilse bile bu oturumda tekrar sorma

    // Tarayici kamerasini birak (cakismasin).
    try {
      await _controller.stop();
      _scanning = false;
    } catch (_) {}

    await PriceCheckChannel.speak('Ürün fotoğrafı çekilecek');

    final path = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => QuickPhotoCaptureScreen(
          productName: name,
          barcode: barcode,
        ),
      ),
    );

    if (path == null || path.isEmpty) return false; // kullanici vazgecti
    _lastPhotoPath = path;

    // Ortak yerel veritabanina yaz — her yerden erisilsin, offline fallback.
    try {
      await _barcodeDs.setLocalImage(barcode, path: path, productName: name);
    } catch (_) {}

    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.statusSafe,
        duration: const Duration(seconds: 2),
        content: Text('Fotoğraf kaydedildi: $name'),
      ),
    );
    return true;
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  REYON KAYDI — fiyat kontrol ile ES ZAMANLI
  /// ──────────────────────────────────────────────────────────────────
  ///  Reyon modu aciksa, kontrol edilen sistem urununu secili reyon
  ///  hucresine (sutun/raf) ekler. Fotograf zaten fiyat kontrol sirasinda
  ///  cekildigi/bulundugu icin YENIDEN cektirmez — _lastPhotoPath yeniden
  ///  kullanilir. Ayni barkod o hucrede zaten varsa tekrar eklemez.
  /// ══════════════════════════════════════════════════════════════════
  Future<void> _maybeAddToReyon() async {
    if (!_reyonMode || _reyonUnit == null) return;
    final barcode = _systemBarcode?.trim();
    final name = _systemProductName?.trim();
    if (barcode == null || barcode.isEmpty) return;
    if (name == null || name.isEmpty || _looksLikeStaticFormLabel(name)) return;

    try {
      // Ayni barkod bu hucrede zaten var mi? Varsa tekrar ekleme.
      final existing = await ShelfLayoutService.instance
          .getSlotsInCell(_reyonUnit!.id!, _reyonSection, _reyonRow);
      if (existing.any((s) => s.barcode == barcode)) return;

      await ShelfLayoutService.instance.addSlot(
        unitId: _reyonUnit!.id!,
        sectionNo: _reyonSection,
        rowNo: _reyonRow,
        barcode: barcode,
        productName: name,
        photoPath: _lastPhotoPath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.primary,
          duration: const Duration(milliseconds: 1400),
          content: Text(
              '$name → ${_reyonUnit!.name} · Sütun $_reyonSection · Raf $_reyonRow'),
        ),
      );
    } catch (_) {}
  }

  /// Reyon modunu ac/kapat. Acarken reyon + baslangic sutun/raf sectirir.
  Future<void> _toggleReyonMode() async {
    if (_reyonMode) {
      setState(() => _reyonMode = false);
      return;
    }
    final units = await ShelfLayoutService.instance.getUnitSummaries();
    if (!mounted) return;
    if (units.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Önce Depo > Reyon Dizilim\'den bir reyon oluşturun.'),
        ),
      );
      return;
    }

    ShelfUnit chosen = _reyonUnit ?? units.first.unit;
    int section = _reyonSection;
    int row = _reyonRow;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 14, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reyon Kaydı',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  'Fiyat kontrol ederken okunan her ürün buradaki hücreye eklenir.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
              const SizedBox(height: 16),
              // Reyon secimi
              DropdownButtonFormField<int>(
                value: chosen.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reyon'),
                items: units
                    .map((u) => DropdownMenuItem(
                          value: u.unit.id,
                          child: Text(
                              '${u.unit.name} (${u.unit.sections} sütun)'),
                        ))
                    .toList(),
                onChanged: (v) {
                  final u = units.firstWhere((e) => e.unit.id == v).unit;
                  setS(() {
                    chosen = u;
                    if (section > u.sections) section = 1;
                  });
                },
              ),
              const SizedBox(height: 14),
              _reyonStepper('Sütun', section, 1, chosen.sections,
                  (v) => setS(() => section = v)),
              const SizedBox(height: 10),
              _reyonStepper(
                  'Raf', row, 1, 99, (v) => setS(() => row = v)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Kaydı Başlat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true && mounted) {
      setState(() {
        _reyonMode = true;
        _reyonUnit = chosen;
        _reyonSection = section;
        _reyonRow = row;
      });
    }
  }

  Widget _reyonStepper(
      String label, int value, int min, int max, ValueChanged<int> onCh) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label)),
        IconButton(
          onPressed: value > min ? () => onCh(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        Container(
          width: 46,
          alignment: Alignment.center,
          child: Text('$value',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        IconButton(
          onPressed: value < max ? () => onCh(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }

  /// Ekran uzerindeki "Sonraki raf" — ayni sutunda bir alt rafa gec.
  void _reyonNextRow() {
    setState(() => _reyonRow++);
    _reyonToast('Raf $_reyonRow');
  }

  /// "Sonraki sütun" — bir sonraki sutunun 1. rafina gec.
  void _reyonNextSection() {
    if (_reyonUnit == null) return;
    setState(() {
      if (_reyonSection < _reyonUnit!.sections) {
        _reyonSection++;
      }
      _reyonRow = 1;
    });
    _reyonToast('Sütun $_reyonSection · Raf 1');
  }

  void _reyonToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 900),
      content: Text('Reyon konumu: $msg'),
    ));
  }

  /// Reyon modu aktifken ekranin ustunde gorunen konum seridi: mevcut
  /// reyon/sutun/raf + "Sonraki raf" / "Sonraki sütun" / kapat.
  Widget _reyonBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.accent.withOpacity(0.18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded,
              size: 18, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_reyonUnit?.name ?? "Reyon"} · Sütun $_reyonSection · Raf $_reyonRow',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _reyonBarBtn('Sonraki raf', Icons.arrow_downward_rounded,
              _reyonNextRow),
          const SizedBox(width: 4),
          _reyonBarBtn('Sonraki sütun', Icons.arrow_forward_rounded,
              _reyonNextSection),
          const SizedBox(width: 4),
          InkWell(
            onTap: _toggleReyonMode,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reyonBarBtn(String tip, IconData icon, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 16, color: Colors.black),
        ),
      ),
    );
  }

  ///  - wrongLabel        : etiket baska urune ait -> dogru etiket basilmali
  ///  - wrongLabelPriceOk : fiyat tutuyor ama etiket yanlis urunun -> basilmali
  ///  - mismatch          : etiketteki fiyat eski/yanlis -> basilmali
  ///  - match / noSystem  : basim gerekmez (noSystem'de zaten karsilastirma yok)
  bool _needsNewLabel(_CompareResult r) =>
      r == _CompareResult.wrongLabel ||
      r == _CompareResult.wrongLabelPriceOk ||
      r == _CompareResult.mismatch;

  void _scheduleAutoRescan() {
    _autoRescanTimer?.cancel();
    _autoRescanTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && _result != null && !_scanning) {
        _scanAgain();
      }
    });
  }

  _CompareResult _compare({
    required double labelPrice,
    required String labelBarcode,
    required double? systemPrice,
    required String? systemBarcode,
  }) {
    if (systemPrice == null) return _CompareResult.noSystem;

    // 1 kurus hassasiyet (kayan nokta hatasini tolere et).
    final priceSame = (labelPrice - systemPrice).abs() < 0.005;

    // YANLIS ETIKET: QR'daki barkod ile sistemdeki barkod farkliysa, bu
    // etiket bu urune ait degildir. (Barkodlardan biri yoksa bu kontrolu
    // atla; sadece fiyata bak.)
    final barcodeMismatch = systemBarcode != null &&
        labelBarcode.isNotEmpty &&
        labelBarcode != '—' &&
        labelBarcode != systemBarcode;

    if (barcodeMismatch) {
      // v3: Fiyat TUTUYOR ama etiket baska bir urune ait. Eskiden bu durum
      // duz "Yanlış etiket" olarak isaretleniyordu ve kullanici fiyatin
      // dogru oldugunu goremiyordu. Artik ayri bir sonuc.
      return priceSame
          ? _CompareResult.wrongLabelPriceOk
          : _CompareResult.wrongLabel;
    }

    return priceSame ? _CompareResult.match : _CompareResult.mismatch;
  }

  Future<void> _announce(
      _CompareResult result, double labelPrice, double? systemPrice) async {
    switch (result) {
      case _CompareResult.match:
        await PriceCheckChannel.vibrate(mismatch: false);
        await PriceCheckChannel.speak('Doğru');
        break;
      case _CompareResult.mismatch:
        await PriceCheckChannel.vibrate(mismatch: true);
        await PriceCheckChannel.speak('Yanlış fiyat');
        break;
      case _CompareResult.wrongLabel:
        await PriceCheckChannel.vibrate(mismatch: true);
        await PriceCheckChannel.speak('Yanlış etiket');
        break;
      case _CompareResult.wrongLabelPriceOk:
        // Fiyat dogru oldugu icin "yanlis fiyat" alarmi vermiyoruz; ama
        // etiket baska urune ait oldugundan yine de UYARI titresimi veriyoruz.
        await PriceCheckChannel.vibrate(mismatch: true);
        await PriceCheckChannel.speak('Fiyat doğru, etiket yanlış');
        break;
      case _CompareResult.noSystem:
        await PriceCheckChannel.vibrate(mismatch: true);
        await PriceCheckChannel.speak('Sistem fiyatı yok');
        break;
    }
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  ETIKET BASIMINA GONDER — KAYAN PENCERE (bottom sheet)
  /// ──────────────────────────────────────────────────────────────────
  ///  Hatali bir sonuctan (yanlis etiket / yanlis fiyat) hemen sonra acilir.
  ///  Kullanici:
  ///    1) Etiket tipini secer (Kalın Reyon / İnce Reyon / A4 / A4 İkili /
  ///       A4 Üçlü) — Etiket Basim ekranindaki AYNI 5 liste.
  ///    2) Adedi belirler (- / + veya hazir 1-2-3-5-10 secenekleri).
  ///    3) "Etiket Basıma Ekle" der.
  ///  Urun, LabelPendingQueueService kuyruguna yazilir; Etiket Basim ekrani
  ///  bir sonraki acilisinda kuyrugu bosaltip ilgili sekmeye ekler (mevcut
  ///  "Fiyat Değişim'den gönder" akisiyla BIREBIR ayni mekanizma — yeni bir
  ///  paralel sistem kurulmadi).
  ///
  ///  HANGI URUN GONDERILIR? Her zaman SISTEMDEKI urun (sistem barkodu +
  ///  sistem urun adi). Cunku "yanlis etiket" durumunda raftaki etiket zaten
  ///  BASKA bir urune aittir; basilmasi gereken, sistemin gosterdigi dogru
  ///  urunun etiketidir.
  /// ══════════════════════════════════════════════════════════════════

  /// Kullanicinin en son sectigi etiket tipi — bir sonraki teklifte hazir
  /// gelsin diye hatirlanir (reyonda ayni tip pes pese kullanilir).
  static LabelGroup _lastLabelGroup = LabelGroup.inceRon;

  Future<void> _offerLabelPrint(_CompareResult result) async {
    final barcode = _systemBarcode ?? _labelBarcode;
    if (!mounted || barcode == null || barcode.isEmpty || barcode == '—') {
      return;
    }
    final productName = _systemProductName?.trim();

    // Gorme dostu: pencere acilirken soruyu sesli de sor.
    await PriceCheckChannel.speak('Etiket basımına eklensin mi?');

    LabelGroup group = _lastLabelGroup;
    int qty = 1;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 12,
                bottom: 18 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.local_printshop_rounded,
                          color: _resultColor(result), size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Etiket basım sayfasına eklensin mi?',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _labelReasonText(result),
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                  const SizedBox(height: 14),

                  // ── URUN OZETI ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName?.isNotEmpty == true
                              ? productName!
                              : 'Ürün adı okunamadı',
                          style: TextStyle(
                            color: productName?.isNotEmpty == true
                                ? Colors.white
                                : AppTheme.textTertiary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Barkod: $barcode'
                          '${_systemStockCode != null ? '  •  Stok: $_systemStockCode' : ''}'
                          '${_systemPrice != null ? '  •  ${_systemPrice!.toStringAsFixed(2)} ₺' : ''}',
                          style: TextStyle(
                              color: AppTheme.textTertiary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── ETIKET TIPI ──
                  Text('Etiket tipi',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: LabelGroup.values.map((g) {
                      final selected = g == group;
                      return ChoiceChip(
                        label: Text(g.title),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => setSheet(() => group = g),
                        backgroundColor: AppTheme.surfaceAlt,
                        selectedColor: AppTheme.primary,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : AppTheme.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: selected ? AppTheme.primary : AppTheme.hairline,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── ADET ──
                  Text('Adet',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _qtyButton(
                        icon: Icons.remove_rounded,
                        onTap: qty > 1
                            ? () => setSheet(() => qty--)
                            : null,
                      ),
                      Container(
                        width: 68,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.hairline),
                        ),
                        child: Text('$qty',
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                      ),
                      _qtyButton(
                        icon: Icons.add_rounded,
                        onTap: qty < 99 ? () => setSheet(() => qty++) : null,
                      ),
                      const SizedBox(width: 12),
                      // Hazir adetler — reyonda hizli secim icin.
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 6,
                          children: const [1, 2, 3, 5, 10].map((n) {
                            return ActionChip(
                              label: Text('$n'),
                              onPressed: () => setSheet(() => qty = n),
                              backgroundColor: qty == n
                                  ? AppTheme.primary.withOpacity(0.3)
                                  : AppTheme.surfaceAlt,
                              labelStyle: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12),
                              side: BorderSide(color: AppTheme.hairline),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── BUTONLAR ──
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetCtx).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                              side: BorderSide(color: AppTheme.hairline),
                            ),
                            child: const Text('Vazgeç',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.statusSafe,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              _lastLabelGroup = group;
                              await LabelPendingQueueService.instance.push(
                                barcode: barcode,
                                productName: (productName?.isNotEmpty == true)
                                    ? productName!
                                    : barcode,
                                stockCode: _systemStockCode,
                                groupKey: group.name,
                                quantity: qty,
                                source: 'price_check',
                              );
                              if (sheetCtx.mounted) {
                                Navigator.of(sheetCtx).pop(true);
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 24),
                            label: Text('$qty adet ekle',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || added != true) return;

    await PriceCheckChannel.speak('Etiket basımına eklendi');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.statusSafe,
        duration: const Duration(seconds: 3),
        content: Text(
            '${_lastLabelGroup.title} listesine eklendi ($qty adet). '
            'Etiket Basım ekranını açtığınızda listeye düşecek.'),
        action: SnackBarAction(
          label: 'AÇ',
          textColor: Colors.white,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LabelPrintScreen()),
          ),
        ),
      ),
    );
  }

  Widget _qtyButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(onTap == null ? 0.03 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Icon(icon,
            color: onTap == null ? AppTheme.hairline : Colors.white, size: 24),
      ),
    );
  }

  /// Kayan penceredeki "neden" satiri — kullanici hangi hata yuzunden etiket
  /// basmasi gerektigini gorsun.
  String _labelReasonText(_CompareResult r) {
    switch (r) {
      case _CompareResult.wrongLabel:
        return 'Raftaki etiket başka bir ürüne ait. Doğru ürünün etiketi basılmalı.';
      case _CompareResult.wrongLabelPriceOk:
        return 'Fiyat doğru ama etiket başka ürünün. Doğru ürünün etiketi basılmalı.';
      case _CompareResult.mismatch:
        return 'Etiketteki fiyat sistemle uyuşmuyor. Etiket yenilenmeli.';
      case _CompareResult.match:
      case _CompareResult.noSystem:
        return '';
    }
  }

  /// Sonuc rengi (hem AppBar hem kayan pencere ikonu icin ortak kaynak).
  Color _resultColor(_CompareResult r) {
    switch (r) {
      case _CompareResult.match:
        return AppTheme.statusSafe;
      case _CompareResult.mismatch:
      case _CompareResult.wrongLabel:
        return AppTheme.statusExpired;
      case _CompareResult.wrongLabelPriceOk:
      case _CompareResult.noSystem:
        return AppTheme.statusWarning;
    }
  }

  Future<void> _scanAgain({bool clearSystem = true}) async {
    _autoRescanTimer?.cancel();
    // Auto-flow'da sirket uygulamasi ARKA PLANDA oldugu icin sistem verisini
    // yeniden okuyamayiz; bu yuzden native'in okudugu degeri KORURUZ
    // (clearSystem=false). Normal akista ise yeni urun icin temizleriz.
    if (clearSystem) {
      await PriceCheckChannel.clearLastSystemPrice();
    }
    setState(() {
      _result = null;
      _labelBarcode = null;
      _labelPrice = null;
      _systemPrice = null;
      _systemBarcode = null;
      _systemStockCode = null;
      _systemProductName = null;
      _busy = false;
      _scanning = true;
    });
    await _controller.start();
  }

  Future<void> _refreshServiceStatus() async {
    final on = await PriceCheckChannel.isServiceRunning();
    if (mounted) setState(() => _serviceOn = on);
  }

  /// Split-screen / freeform (kucuk pencere) modunu tespit eder.
  ///
  /// NEDEN GEREKLI: Kullanici telefonu split-screen'e aldiginda (veya bir
  /// Android cihazda freeform/kucuk pencere modunda actiginda) Fiyat
  /// Kontrol ekrani cok az dikey alana sahip olur; sabit yukseklikteki
  /// AppBar bu durumda orantisiz buyuk bir pay kaplar ve kamera/sonuc
  /// alani sikisir. Bu yuzden AppBar'i byle pencerelerde TAMAMEN
  /// KALDIRIYORUZ, normal tam ekran kullanımda ise dokunmuyoruz.
  ///
  /// TESPIT YONTEMI: Mutlak bir "kucuk pencere modu" API'si Flutter'da
  /// yok (Android'in isInMultiWindowMode'u native taraf gerektirir); bunun
  /// yerine MediaQuery'den gelen mevcut pencere boyutunu cihazin GERCEK
  /// (fiziksel) ekran boyutuyla karsilastiriyoruz. Pencere yuksekligi,
  /// fiziksel ekran yuksekliginin belirli bir esigin (yaklasik %65)
  /// ALTINDAYSA, bu uygulamanin ekranin tamamini kaplamadigi -> split-
  /// screen/freeform modda oldugu anlamina gelir. Oran tabanli oldugu icin
  /// farkli cihaz/cozunurluklerde de dogru calisir.
  bool _isSmallWindowMode(BuildContext context) {
    final view = View.of(context);
    final physicalSize = view.physicalSize;
    final devicePixelRatio = view.devicePixelRatio;
    if (physicalSize.isEmpty || devicePixelRatio == 0) return false;
    final fullScreenHeight = physicalSize.height / devicePixelRatio;
    final currentHeight = MediaQuery.sizeOf(context).height;
    if (fullScreenHeight <= 0) return false;
    return (currentHeight / fullScreenHeight) < 0.65;
  }

  @override
  Widget build(BuildContext context) {
    final smallWindow = _isSmallWindowMode(context);
    return Scaffold(
      backgroundColor: Colors.black,
      // Kucuk pencere (split-screen/freeform) modunda AppBar TAMAMEN
      // KALDIRILIR — dar alanda yer kazanmak icin. Normal tam ekranda
      // her zamanki gibi gosterilir.
      appBar: smallWindow
          ? null
          : AppBar(
              backgroundColor: _appBarColor(),
              foregroundColor: Colors.white,
              title: const Text('Fiyat Kontrol'),
              actions: [
                // ── OTOMATIK GEZINME anahtari ──
                // Acikken: sirket uygulamasi yeni urun gosterince bu
                // uygulama otomatik one gelir; sonuc sonrasi 2 sn'de sirket
                // uygulamasina geri doner. Kapaliyken her sey elle.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _autoFlow
                          ? Icons.sync_rounded
                          : Icons.sync_disabled_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    Switch(
                      value: _autoFlow,
                      onChanged: _setAutoFlow,
                      activeColor: Colors.white,
                      activeTrackColor: Colors.white54,
                      inactiveThumbColor: Colors.white70,
                      inactiveTrackColor: Colors.white24,
                    ),
                  ],
                ),
                // Okunan urunler (onay) sayfasi — rozette bekleyen sayisi.
                ValueListenableBuilder<List<PendingProduct>>(
                  valueListenable: pendingProductsQueue,
                  builder: (_, items, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Okunan ürünler',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PendingProductsScreen()),
                        ),
                        icon: const Icon(Icons.inventory_2_rounded),
                      ),
                      if (items.isNotEmpty)
                        Positioned(
                          right: 6,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppTheme.statusExpired,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            child: Text('${items.length}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ),
                // ── REYON KAYDI butonu ── (fiyat kontrol + reyon es zamanli)
                IconButton(
                  tooltip: 'Reyon kaydı',
                  onPressed: _toggleReyonMode,
                  icon: Icon(
                    _reyonMode
                        ? Icons.grid_view_rounded
                        : Icons.grid_view_outlined,
                    color: _reyonMode ? AppTheme.accent : Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Servis durumunu yenile',
                  onPressed: _refreshServiceStatus,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
      body: SafeArea(
        // AppBar yokken (kucuk pencere) geri donus icin minik bir kapatma
        // kontrolu olmazsa kullanici ekrandan cikamaz. SafeArea + bu satir
        // sadece smallWindow durumunda gorunur, normal modda hicbir sey
        // degismez.
        child: Column(
          children: [
            if (smallWindow) _smallWindowBar(),
            if (_reyonMode) _reyonBar(),
            if (!_serviceOn) _serviceWarning(),
            if (_serviceOn) _liveSystemCard(),
            Expanded(
              child: _result == null ? _scannerView() : _resultView(),
            ),
          ],
        ),
      ),
    );
  }

  /// AppBar'in yerini tutan, kucuk pencere modunda gosterilen minimal
  /// ust serit: geri donus + okunan urunler kisayolu. AppBar'in
  /// kapladigi standart yuksekligin (56) cok altinda, ince bir serit.
  Widget _smallWindowBar() {
    return Container(
      color: _appBarColor(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Geri',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            iconSize: 20,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
          const Expanded(
            child: Text('Fiyat Kontrol',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          ValueListenableBuilder<List<PendingProduct>>(
            valueListenable: pendingProductsQueue,
            builder: (_, items, __) => IconButton(
              tooltip: 'Okunan ürünler (${items.length})',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PendingProductsScreen()),
              ),
              icon: const Icon(Icons.inventory_2_rounded, color: Colors.white),
              iconSize: 20,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  /// CANLI sistem verisi kartı: erisilebilirlik servisi sirket
  /// uygulamasinda urunu gordukce surekli guncellenir (QR okutmaya gerek
  /// yok). Hangi urunde oldugunu ve sistem fiyatini anlik gosterir.
  Widget _liveSystemCard() {
    final hasData = _livePrice != null || _liveProductName != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasData
              ? AppTheme.primaryLight.withOpacity(0.5)
              : AppTheme.hairline,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasData ? Icons.sensors_rounded : Icons.sensors_off_rounded,
            color: hasData ? AppTheme.primaryLight : Colors.white38,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasData
                      ? (_liveProductName ?? 'Ürün okunuyor…')
                      : 'Sistemde ürün bekleniyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_liveBarcode != null)
                  Text(
                    'Barkod: $_liveBarcode'
                    '${_liveStockCode != null ? '  •  Stok: $_liveStockCode' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _livePrice != null
                ? '${_livePrice!.toStringAsFixed(2)} ₺'
                : '—',
            style: TextStyle(
              color: _livePrice != null
                  ? AppTheme.primaryLight
                  : Colors.white38,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// App bar rengi duruma gore: dogru=yesil, yanlis fiyat/etiket=kirmizi,
  /// fiyat dogru+etiket yanlis / sistem fiyati yok=sari, sonuc yok=mor.
  Color _appBarColor() {
    final r = _result;
    if (r == null) return AppTheme.primary;
    return _resultColor(r);
  }


  Widget _serviceWarning() {
    return Container(
      width: double.infinity,
      color: AppTheme.statusWarning.withOpacity(0.18),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppTheme.statusWarning, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Erisilebilirlik servisi kapali. Sistem fiyati okunamaz.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () async {
                await PriceCheckChannel.openAccessibilitySettings();
              },
              child: const Text('Erisilebilirlik Ayarlarini Ac'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scannerView() {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        const ScanOverlay(hint: 'Etiket barkodunu çerçeveye getirin'),
      ],
    );
  }

  Widget _resultView() {
    final r = _result!;
    final Color bg;
    final IconData icon;
    final String title;
    switch (r) {
      case _CompareResult.match:
        bg = AppTheme.statusSafe;
        icon = Icons.check_circle_rounded;
        title = 'FIYATLAR UYUYOR';
        break;
      case _CompareResult.mismatch:
        bg = AppTheme.statusExpired;
        icon = Icons.cancel_rounded;
        title = 'FIYAT UYUSMUYOR';
        break;
      case _CompareResult.wrongLabel:
        bg = AppTheme.statusExpired;
        icon = Icons.wrong_location_rounded;
        title = 'YANLIŞ ETİKET';
        break;
      case _CompareResult.wrongLabelPriceOk:
        bg = AppTheme.statusWarning;
        icon = Icons.swap_horiz_rounded;
        title = 'FİYAT DOĞRU\nETİKET YANLIŞ';
        break;
      case _CompareResult.noSystem:
        bg = AppTheme.statusWarning;
        icon = Icons.help_rounded;
        title = 'SISTEM FIYATI YOK';
        break;
    }

    return Container(
      color: bg,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 110, color: Colors.white),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 28),
          if (_systemProductName != null) ...[
            Text(
              _systemProductName!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
          ],
          _priceRow('Etiket', _labelPrice),
          const SizedBox(height: 12),
          _priceRow('Sistem', _systemPrice),
          if (r == _CompareResult.wrongLabel ||
              r == _CompareResult.wrongLabelPriceOk) ...[
            const SizedBox(height: 16),
            Text(
              'Etiket barkodu: ${_labelBarcode ?? "—"}\n'
              'Sistem barkodu: ${_systemBarcode ?? "—"}\n'
              '${r == _CompareResult.wrongLabelPriceOk ? "Fiyatlar aynı ama bu etiket başka bir ürüne ait. Etiketi doğru ürünle değiştirin." : "Bu etiket bu ürüne ait değil. Diğer etiketleri okutun."}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.95)),
            ),
          ] else if (_labelBarcode != null) ...[
            const SizedBox(height: 16),
            Text('Barkod: $_labelBarcode',
                style: TextStyle(color: Colors.white.withOpacity(0.85))),
          ],
          if (r == _CompareResult.noSystem) ...[
            const SizedBox(height: 16),
            Text(
              'Once sirket uygulamasinda barkodu okutun, sonra tekrar deneyin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.95)),
            ),
          ],
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: bg,
                textStyle: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
              ),
              onPressed: _scanAgain,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
              label: const Text('TEKRAR OKUT'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, double? value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label: ',
            style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 22,
                fontWeight: FontWeight.w600)),
        Text(
          value == null ? '—' : '${value.toStringAsFixed(2)} ₺',
          style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

/// Karsilastirma sonuclari:
///  - [match]              : barkod ayni + fiyat ayni  -> "Doğru"
///  - [mismatch]           : barkod ayni + fiyat farkli -> "Yanlış fiyat"
///  - [wrongLabel]         : barkod FARKLI + fiyat da farkli -> "Yanlış etiket"
///  - [wrongLabelPriceOk]  : barkod FARKLI ama fiyat AYNI    -> "Fiyat doğru,
///    etiket yanlış". (v3'te eklendi.) Bu durum pratikte cok kritiktir:
///    fiyat tuttugu icin gozden kacar, ama raftaki etiket BASKA bir urune
///    aittir — musteri yanlis urun bilgisi gorur. Kirmizi degil TURUNCU ile
///    gosterilir; cunku fiyat hatasi YOK, etiket yerlesimi hatasi VAR.
///  - [noSystem]           : sistem fiyati okunamadi -> "Sistem fiyatı yok"
enum _CompareResult { match, mismatch, wrongLabel, wrongLabelPriceOk, noSystem }
