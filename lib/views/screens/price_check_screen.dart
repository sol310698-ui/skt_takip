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

class _PriceCheckScreenState extends State<PriceCheckScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.all],
    autoStart: false,
  );

  bool _scanning = false;
  bool _busy = false;
  bool _serviceOn = false;
  bool _overlayOn = false; // yuzen baloncuk acik mi

  // ── TANI (debug) ──
  bool _debugOpen = true; // tani paneli acik mi
  Timer? _debugTimer;
  Timer? _autoRescanTimer; // sonuc sonrasi otomatik yeniden tarama
  Map<String, dynamic> _debug = {};

  // Son sonuc
  String? _labelBarcode;
  double? _labelPrice;
  double? _systemPrice;
  String? _systemBarcode;
  String? _systemProductName;
  _CompareResult? _result;

  // TANI: en son okunan QR ham metni + parse sonucu
  String? _lastQrRaw;
  String? _lastQrNote;

  @override
  void initState() {
    super.initState();
    _init();
    _initOverlay();
    // Baloncuktan anlik "QR modu ac" cagrisi gelirse taramaya gec.
    PriceCheckChannel.setQuickScanHandler(() {
      if (mounted && !_scanning) _scanAgain();
    });
    // TANI: her saniye servisin durumunu cek ve goster.
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final info = await PriceCheckChannel.getDebugInfo();
      if (mounted) {
        setState(() {
          _debug = info;
          if (info.containsKey('running')) {
            _serviceOn = info['running'] == true;
          }
        });
      }
    });
  }

  Future<void> _initOverlay() async {
    final running = await PriceCheckChannel.isOverlayRunning();
    // Uygulama baloncuktan acildiysa hemen QR moduna gec.
    final quick = await PriceCheckChannel.consumeQuickScan();
    if (mounted) {
      setState(() => _overlayOn = running);
      if (quick && !_scanning) _scanAgain();
    }
  }

  Future<void> _toggleOverlay(bool on) async {
    if (on) {
      final can = await PriceCheckChannel.canDrawOverlays();
      if (!can) {
        await PriceCheckChannel.requestOverlayPermission();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '"Üstte göster" iznini verin, sonra anahtarı tekrar açın.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return; // izin verilince kullanici tekrar acar
      }
      final ok = await PriceCheckChannel.startOverlay();
      if (mounted) setState(() => _overlayOn = ok);
    } else {
      await PriceCheckChannel.stopOverlay();
      if (mounted) setState(() => _overlayOn = false);
    }
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
    _debugTimer?.cancel();
    _autoRescanTimer?.cancel();
    _controller.dispose();
    super.dispose();
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final parsed = _parseLabelQr(raw);
    if (parsed == null) {
      // QR okundu AMA fiyat cikarilamadi. Taniya yaz, taramaya devam et.
      setState(() {
        _lastQrRaw = raw;
        _lastQrNote = 'Okundu ama fiyat bulunamadı';
      });
      return;
    }

    setState(() {
      _lastQrRaw = raw;
      _lastQrNote = 'Fiyat: ${parsed.price}';
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
    if (systemBarcode != null &&
        sys.productName != null &&
        sys.productName!.trim().isNotEmpty) {
      addPendingProduct(PendingProduct(
        barcode: systemBarcode,
        stockCode: sys.stockCode,
        productName: sys.productName!.trim(),
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

    // Baloncuk (overlay) acikssa rengini guncelle + otomatik arka plana
    // donerek kullaniciyi sirket uygulamasina birak.
    if (_overlayOn) {
      await PriceCheckChannel.updateOverlayState(_overlayStateOf(result));
      // Kisa sure sonucu gosterip arka plana don (sirket uygulamasi one gelir).
      _autoRescanTimer?.cancel();
      _autoRescanTimer = Timer(const Duration(milliseconds: 1400), () async {
        if (mounted) {
          await _scanAgain(); // bir sonraki QR icin hazir tut
          // Uygulamayi arka plana at -> altta duran sirket uygulamasi gelir.
          await SystemNavigator.pop();
        }
      });
      return;
    }

    // OTOMATIK DEVAM: kullanici "Tekrar Okut"a basmak zorunda kalmasin.
    _scheduleAutoRescan();
  }

  String _overlayStateOf(_CompareResult r) {
    switch (r) {
      case _CompareResult.match:
        return 'match';
      case _CompareResult.mismatch:
        return 'mismatch';
      case _CompareResult.wrongLabel:
        return 'wrong';
      case _CompareResult.noSystem:
        return 'nosystem';
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
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
            tooltip: 'Tanı panelini aç/kapat',
            onPressed: () => setState(() => _debugOpen = !_debugOpen),
            icon: Icon(_debugOpen
                ? Icons.bug_report_rounded
                : Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: 'Servis durumunu yenile',
            onPressed: _refreshServiceStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_serviceOn) _serviceWarning(),
          _overlayToggleBar(),
          if (_debugOpen) _debugPanel(),
          Expanded(
            child: _result == null ? _scannerView() : _resultView(),
          ),
        ],
      ),
    );
  }

  Widget _overlayToggleBar() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF14181E),
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          const Icon(Icons.bubble_chart_rounded,
              color: AppTheme.primaryLight, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Yüzen baloncuk (uygulamadan çıkmadan kontrol)',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Switch(
            value: _overlayOn,
            onChanged: _toggleOverlay,
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

  Widget _debugPanel() {
    final running = _debug['running'] == true;
    final price = _debug['price'];
    final raw = _debug['raw'];
    final labelFound = _debug['labelFound'] == true;
    final pkg = _debug['lastPackage'];
    final sample = _debug['screenSample'];
    final lastEvent = _debug['lastEventTime'];
    String lastSeen = '—';
    if (lastEvent is int && lastEvent > 0) {
      final secsAgo =
          ((DateTime.now().millisecondsSinceEpoch - lastEvent) / 1000).round();
      lastSeen = '$secsAgo sn önce';
    }

    Widget line(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(k,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ),
              Expanded(
                child: Text(v,
                    style: TextStyle(
                        color: color ?? Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      color: const Color(0xFF101418),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_rounded,
                  color: Colors.amber, size: 16),
              const SizedBox(width: 6),
              const Text('TANI PANELİ',
                  style: TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          line('Servis açık mı', running ? 'EVET' : 'HAYIR',
              color: running ? Colors.greenAccent : Colors.redAccent),
          line('Son ekran olayı', lastSeen),
          line('Son uygulama', pkg?.toString() ?? '—'),
          line('"Sistem Fiyatı"', labelFound ? 'BULUNDU' : 'bulunamadı',
              color: labelFound ? Colors.greenAccent : Colors.orangeAccent),
          line('Okunan fiyat',
              price == null ? '—' : price.toString(),
              color: price == null ? Colors.orangeAccent : Colors.greenAccent),
          if (raw != null) line('Ham metin', raw.toString()),
          const SizedBox(height: 4),
          line('Son QR', _lastQrRaw ?? 'henüz okunmadı',
              color: _lastQrRaw == null ? Colors.white54 : Colors.cyanAccent),
          if (_lastQrNote != null)
            line('QR durumu', _lastQrNote!,
                color: _lastQrNote!.startsWith('Fiyat')
                    ? Colors.greenAccent
                    : Colors.orangeAccent),
          const SizedBox(height: 4),
          const Text('Ekranda görülen metinler:',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          Text(sample?.toString() ?? '—',
              style: const TextStyle(
                  color: Colors.white, fontSize: 11),
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
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
        Positioned(
          top: 24,
          left: 24,
          right: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '1) Sirket uygulamasinda barkodu okutun (Sistem Fiyati ciksin)\n'
              '2) Buraya gelip etiketin QR kodunu okutun',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ),
        ),
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
