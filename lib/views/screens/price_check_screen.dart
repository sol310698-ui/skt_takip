import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/pending_products_queue.dart';
import '../../core/services/price_check_channel.dart';
import '../../core/theme/app_theme.dart';
import 'pending_products_screen.dart';

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

  // Servis acik/kapali durumunu periyodik kontrol eden zamanlayici.
  // (Eskiden burada gorunur bir "TANI PANELI" de besleniyordu; kullanici
  // istegiyle o panel KALDIRILDI — bu zamanlayici artik SADECE _serviceOn
  // bayragini güncellemek icin var, ekranda hicbir gorunur cikti uretmez.)
  Timer? _serviceStatusTimer;
  StreamSubscription<SystemPriceSnapshot>? _liveSub; // canli sistem verisi
  Timer? _autoRescanTimer; // sonuc sonrasi otomatik yeniden tarama

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
      _systemProductName = sys.productName;
      _result = result;
      _busy = false;
    });

    // Sesli + titresimli geri bildirim.
    await _announce(result, parsed.price, systemPrice);

    // OTOMATIK DEVAM: kullanici "Tekrar Okut"a basmak zorunda kalmasin.
    _scheduleAutoRescan();
  }

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

    // YANLIS ETIKET: QR'daki barkod ile sistemdeki barkod farkliysa, bu
    // etiket bu urune ait degildir. (Barkodlardan biri yoksa bu kontrolu
    // atla; sadece fiyata bak.)
    if (systemBarcode != null &&
        labelBarcode.isNotEmpty &&
        labelBarcode != '—' &&
        labelBarcode != systemBarcode) {
      return _CompareResult.wrongLabel;
    }

    // 1 kurus hassasiyet (kayan nokta hatasini tolere et).
    if ((labelPrice - systemPrice).abs() < 0.005) {
      return _CompareResult.match;
    }
    return _CompareResult.mismatch;
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
      case _CompareResult.noSystem:
        await PriceCheckChannel.vibrate(mismatch: true);
        await PriceCheckChannel.speak('Sistem fiyatı yok');
        break;
    }
  }

  Future<void> _scanAgain() async {
    _autoRescanTimer?.cancel();
    await PriceCheckChannel.clearLastSystemPrice();
    setState(() {
      _result = null;
      _labelBarcode = null;
      _labelPrice = null;
      _systemPrice = null;
      _systemBarcode = null;
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
        color: const Color(0xFF14181E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasData
              ? AppTheme.primaryLight.withOpacity(0.5)
              : Colors.white24,
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
                  style: const TextStyle(
                    color: Colors.white,
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
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
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
  /// sistem fiyati yok=sari, henuz sonuc yok=normal (mor).
  Color _appBarColor() {
    switch (_result) {
      case _CompareResult.match:
        return AppTheme.statusSafe;
      case _CompareResult.mismatch:
      case _CompareResult.wrongLabel:
        return AppTheme.statusExpired;
      case _CompareResult.noSystem:
        return AppTheme.statusWarning;
      case null:
        return AppTheme.primary;
    }
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
        // Tarama cercevesi
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.9), width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
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
          if (r == _CompareResult.wrongLabel) ...[
            const SizedBox(height: 16),
            Text(
              'Etiket barkodu: ${_labelBarcode ?? "—"}\n'
              'Sistem barkodu: ${_systemBarcode ?? "—"}\n'
              'Bu etiket bu ürüne ait değil. Diğer etiketleri okutun.',
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

enum _CompareResult { match, mismatch, wrongLabel, noSystem }
