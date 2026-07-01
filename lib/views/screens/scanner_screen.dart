import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/services/camera_helper.dart';
import '../../core/services/flow_prefs.dart';
import '../../core/services/gemini_ocr_service.dart';
import '../../core/utils/date_utils.dart' as date_utils;
import '../../core/theme/app_theme.dart';

/// SKT tarama ekraninin donus sonucu: tarih (zorunlu) + varsa cekilen
/// etiket fotografinin yolu (urun adi OCR'i icin formda yeniden kullanilir).
/// DateTime(1900) = "elle gir" secildi (tarih yok, formda manuel girilecek).
class ScanOutcome {
  final DateTime date;
  final String? labelPhotoPath;
  const ScanOutcome(this.date, {this.labelPhotoPath});
}

/// ════════════════════════════════════════════════════════════════════
///  SKT TARA — basit, gorme dostu manuel tarih okuma ekrani.
///
///  Akis: kamera canli onizleme -> kullanici tarihi cerceveye getirir ->
///  "Fotograf Cek" -> cerceve ici kirpilir, buyutulur -> kullanici tarihi
///  elle girer. Otomatik OCR YOK (donma/karmaşa kaynagiydi).
///
///  Kamera yonetimi tamamen "camera" paketi ile, net yasam dongusu:
///  initState -> init, dispose -> birak, app arka plan -> duraklat/devam.
///
///  prefillBarcode: bu ekrana gelmeden once barkod zaten tarandiysa
///  (yeni akis: once barkod, sonra SKT), bilgi amacli basliktirilir.
/// ════════════════════════════════════════════════════════════════════
class ScannerScreen extends StatefulWidget {
  final String? prefillBarcode;

  const ScannerScreen({super.key, this.prefillBarcode});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _torchOn = false;

  // CANLI YAKINLASTIRMA (kucuk yazilari gozle okumak icin).
  // Alttaki kaydirilabilir slider ile canli onizleme buyutulur. Boylece
  // kullanici etiketteki kucuk SKT'yi yakinlastirip KENDI gozuyle okur,
  // sonra normal akistan (Foto/AI/Elle) devam eder.
  double _liveZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // Uygulama arka plana gidince kamerayi birak, donunce yeniden kur.
  // Kilit/parmak izi/foto cekme gibi gecislerde de tetiklenir; bu yuzden
  // yeniden kurulum YARIS'a dayanikli olmali (asagidaki _initCamera tek
  // seferde calisir, ust uste cagrilsa bile bozulmaz).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final c = _controller;
      if (c != null) {
        _controller = null;
        _initFuture = null;
        c.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      // One donunce kamerayi yeniden kur (zaten kuruluysa _initCamera
      // kendini korur).
      _initCamera();
    }
  }

  bool _initializing = false;

  Future<void> _initCamera() async {
    // Zaten kurulu veya kuruluyorsa tekrar baslatma (yaris korumasi).
    if (_initializing) return;
    if (_controller != null && _controller!.value.isInitialized) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      // Arka kamerayi sec.
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      final initFuture = controller.initialize();
      _initFuture = initFuture;
      await initFuture;
      if (!mounted) {
        controller.dispose();
        return;
      }
      // Bu init sirasinda ekran arka plana gidip controller sifirlandiysa
      // (yaris), yeni controller'i birak ve cik.
      if (_controller != null) {
        controller.dispose();
        return;
      }
      // Onceki zoom'u koru.
      setState(() {
        _controller = controller;
        _liveZoom = 1.0;
      });

      // Canli zoom araligini al (cihaza gore degisir, genelde 1x..~8x).
      try {
        final maxZ = await controller.getMaxZoomLevel();
        final minZ = await controller.getMinZoomLevel();
        await controller.setZoomLevel(minZ);
        if (mounted) {
          setState(() {
            _minZoom = minZ;
            _maxZoom = maxZ > 8.0 ? 8.0 : maxZ;
            _liveZoom = minZ;
          });
        }
      } catch (_) {
        // Zoom desteklenmiyorsa slider gizlenir.
      }
    } catch (_) {
      // Kamera acilamadi — kullanici elle girebilir.
    } finally {
      _initializing = false;
    }
  }

  /// Canli onizleme zoom'unu uygular (slider'dan cagrilir).
  Future<void> _setLiveZoom(double value) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final z = value.clamp(_minZoom, _maxZoom).toDouble();
    setState(() {
      _liveZoom = z;
    });
    try {
      await c.setZoomLevel(z);
    } catch (_) {}
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      _torchOn = !_torchOn;
      await c.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// "Elle gir": kamera ekranindan AYRILMADAN hizli tarih giris kutusu acar.
  /// Kullanici tarihi burada girer; kamera bırakilip o tarihle forma gecilir.
  /// Boylece form acilirken (kamera kapanma + yeni ekran + klavye) ust uste
  /// yuklenmez, kasma olmaz.
  Future<void> _manual() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickDateSheet(),
    );
    if (picked != null && mounted) {
      Navigator.of(context).pop(ScanOutcome(picked));
    }
  }

  Future<void> _openAi() async {
    final result = await showModalBottomSheet<ScanOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: !FlowPrefs.instance.fastFlow,
      builder: (_) => _AiScanSheet(fastFlow: FlowPrefs.instance.fastFlow),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      // Kamera onizlemesi status bar arkasina kadar uzansin.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Text(
          widget.prefillBarcode != null && widget.prefillBarcode!.isNotEmpty
              ? 'SKT Tara · ${widget.prefillBarcode}'
              : 'SKT Tara',
        ),
        actions: [
          IconButton(
            icon: Icon(_torchOn
                ? Icons.flash_on_rounded
                : Icons.flash_off_rounded),
            onPressed: ready ? _toggleTorch : null,
            tooltip: 'Flaş',
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Kamera onizleme veya yukleniyor ──
          if (ready)
            Positioned.fill(
              child: _CameraPreviewFitted(controller: c),
            )
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 16),
                  Text('Kamera hazırlanıyor...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),

          // ── Tarama cercevesi (gorsel rehber) ──
          if (ready)
            Center(
              child: IgnorePointer(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.96,
                  height: MediaQuery.of(context).size.width * 0.96 * 0.5,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppTheme.primary.withOpacity(0.9), width: 3),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 0,
                        spreadRadius: 2000,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // (Ust ipucu kaldirildi — gereksiz bilgi, ekrani sadelestirdik.)


          // (Sol ust foto-zoom secici kaldirildi — alttaki canli slider
          //  zaten zoom isini goruyor; ust kisim sadelesti.)


          // ── Canli yakinlastirma slider'i (kucuk yazilari okumak icin) ──
          if (ready && _maxZoom > _minZoom) _buildZoomSlider(),

          // ── Alt aksiyon cubugu ──
          if (ready) _buildActionBar(),
        ],
      ),
    );
  }

  /// Sol altta "Hizli Akis" gecisi. Acik iken AI akisi otomatik ilerler.
  /// Tercih kalicidir (FlowPrefs).
  Widget _buildFastFlowToggle() {
    final on = FlowPrefs.instance.fastFlow;
    return InkWell(
      onTap: () async {
        await FlowPrefs.instance.setFastFlow(!on);
        if (mounted) setState(() {});
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on
              ? AppTheme.accent.withOpacity(0.18)
              : AppTheme.background.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? AppTheme.accent : AppTheme.hairline,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.bolt_rounded : Icons.bolt_outlined,
              size: 18,
              color: on ? AppTheme.accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              on ? 'Hızlı Akış: Açık' : 'Hızlı Akış: Kapalı',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Canli yakinlastirma slider'i. Alt aksiyon cubugunun hemen ustunde,
  /// parmakla kaydirilabilir. Kucuk yazilari (SKT) gozle okumak icin canli
  /// onizlemeyi buyutur. Sade ve goz yormayan tasarim.
  Widget _buildZoomSlider() {
    return Positioned(
      left: 16,
      right: 16,
      // Aksiyon cubugunun (Hizli Akis + butonlar) ustunde dursun.
      bottom: 210,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.zoom_out_rounded,
                  color: Colors.white70, size: 22),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: AppTheme.primary.withOpacity(0.2),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 12),
                  ),
                  child: Slider(
                    value: _liveZoom.clamp(_minZoom, _maxZoom).toDouble(),
                    min: _minZoom,
                    max: _maxZoom,
                    onChanged: _setLiveZoom,
                  ),
                ),
              ),
              const Icon(Icons.zoom_in_rounded,
                  color: Colors.white70, size: 22),
              const SizedBox(width: 8),
              // Mevcut zoom seviyesi (ornek "2.4x").
              SizedBox(
                width: 44,
                child: Text(
                  '${_liveZoom.toStringAsFixed(1)}x',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Hizli Akis gecisi (sol altta, kalici) ──
              Align(
                alignment: Alignment.centerLeft,
                child: _buildFastFlowToggle(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // AI ile oku (otomatik)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openAi,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                      label: const Text('AI ile Oku',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Elle gir (kamerada gozle okuyup yaz)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _manual,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      icon: const Icon(Icons.keyboard_rounded, size: 20),
                      label: const Text('Elle Gir',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kamera onizlemesini ekrani dolduracak sekilde (cover) gosterir.
class _CameraPreviewFitted extends StatelessWidget {
  final CameraController controller;
  const _CameraPreviewFitted({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Kamera en-boy oranini koruyarak ekrani doldur (FittedBox cover).
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.width * controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

enum _AiState { idle, captured, sending, done, failed }

class _AiScanSheet extends StatefulWidget {
  /// Hizli akis: acilir acilmaz otomatik foto cek -> otomatik gonder ->
  /// tarih okununca 2 sn geri sayimla otomatik kabul.
  final bool fastFlow;
  const _AiScanSheet({this.fastFlow = false});

  @override
  State<_AiScanSheet> createState() => _AiScanSheetState();
}

class _AiScanSheetState extends State<_AiScanSheet> {
  _AiState _state = _AiState.idle;
  String? _photoPath;
  DateTime? _result;
  String _message = '';

  // Hizli akista otomatik kabul geri sayimi.
  Timer? _autoAcceptTimer;
  int _countdownMs = 0;

  @override
  void initState() {
    super.initState();
    if (widget.fastFlow) {
      // Acilir acilmaz dogrudan foto cekmeyi baslat (ara ekran yok).
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    }
  }

  @override
  void dispose() {
    _autoAcceptTimer?.cancel();
    super.dispose();
  }

  Future<void> _capture() async {
    try {
      final photo = await CameraHelper.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (photo == null) {
        // Hizli akista foto iptal edilirse sheet'i kapat (kullanici vazgecti).
        if (widget.fastFlow && mounted) Navigator.of(context).pop();
        return;
      }
      final persistent = await CameraHelper.persistPhoto(photo.path);
      setState(() {
        _photoPath = persistent;
        _state = _AiState.captured;
      });
      // Hizli akis: foto cekilir cekilmez otomatik gonder.
      if (widget.fastFlow) {
        _sendToAi();
      }
    } catch (e) {
      setState(() {
        _state = _AiState.failed;
        _message = 'Fotoğraf alınamadı: $e';
      });
    }
  }

  /// AI'a gonderme — cekilen fotograf Gemini'ye gonderilir, donen SKT
  /// tarihi _result'a yazilir. Anahtar yoksa/okuma basarisizsa kullaniciya
  /// mesaj gosterilir ve elle girise yonlendirilir.
  Future<void> _sendToAi() async {
    if (_photoPath == null) return;
    setState(() {
      _state = _AiState.sending;
      _message = '';
    });

    try {
      final hasKey = await GeminiOcrService.instance.hasApiKey();
      if (!hasKey) {
        if (!mounted) return;
        setState(() {
          _state = _AiState.failed;
          _message =
              'Gemini API anahtarı tanımlı değil. Fiyat Değişim ekranındaki '
              'AI/Gemini ayarından anahtarınızı girin, ya da elle giriş '
              'kullanın.';
        });
        return;
      }

      final date = await GeminiOcrService.instance
          .extractExpiryDate(File(_photoPath!));
      if (!mounted) return;
      setState(() {
        _result = date;
        _state = _AiState.done;
        _message = '';
      });
      // Hizli akis: tarih okundu, 1.5 sn geri sayimla otomatik kabul.
      // Kullanici bu sure icinde "Dur" derse iptal eder, yanlissa duzeltir.
      if (widget.fastFlow) {
        _startAutoAccept();
      }
    } on GeminiOcrException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _AiState.failed;
        _message = '${e.message}. Tekrar çekebilir veya elle '
            'girebilirsiniz.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _AiState.failed;
        _message = 'Beklenmeyen hata: $e';
      });
    }
  }

  /// Hizli akis: tarih okununca 1.5 sn geri sayim baslatir, sure dolunca
  /// otomatik kabul eder. Kullanici "Dur"a basarsa iptal olur.
  void _startAutoAccept() {
    const totalMs = 1500;
    const tickMs = 100;
    _countdownMs = totalMs;
    setState(() {});
    _autoAcceptTimer?.cancel();
    _autoAcceptTimer =
        Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdownMs -= tickMs);
      if (_countdownMs <= 0) {
        t.cancel();
        _confirm();
      }
    });
  }

  void _cancelAutoAccept() {
    _autoAcceptTimer?.cancel();
    setState(() => _countdownMs = 0);
  }

  void _confirm() {
    _autoAcceptTimer?.cancel();
    if (_result != null) {
      Navigator.of(context)
          .pop(ScanOutcome(_result!, labelPhotoPath: _photoPath));
    }
  }

  void _manual() {
    _autoAcceptTimer?.cancel();
    // Elle gir secildi: tarih yok ama cekilmis fotograf varsa (AI okuma
    // basarisiz oldu ama foto cekildi) onu da tasiyalim; isim OCR'i icin
    // ise yarayabilir.
    Navigator.of(context)
        .pop(ScanOutcome(DateTime(1900), labelPhotoPath: _photoPath));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: AppTheme.accent, size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('AI ile Tarih Oku',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildBody(),
            const SizedBox(height: 20),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _AiState.idle:
        return Text(
          'Tarihi net çerçeveleyip fotoğraflayın. Görüntü AI ile '
          'okunacak (yakında).',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        );
      case _AiState.captured:
        return Column(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.statusSafe, size: 40),
            const SizedBox(height: 8),
            Text('Fotoğraf hazır. AI\'a göndermek için dokunun.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        );
      case _AiState.sending:
        return Column(
          children: [
            CircularProgressIndicator(color: AppTheme.accent),
            SizedBox(height: 12),
            Text('AI\'a gönderiliyor...',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        );
      case _AiState.done:
        final s = _result != null
            ? DateFormat('dd.MM.yyyy').format(_result!)
            : '-';
        return Column(
          children: [
            Text('AI Sonucu',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(s,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.statusSafe)),
            if (_countdownMs > 0) ...[
              const SizedBox(height: 8),
              Text(
                  '${(_countdownMs / 1000).toStringAsFixed(1)} sn içinde otomatik kaydedilecek',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        );
      case _AiState.failed:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.statusWarning.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.statusWarning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _message.isEmpty ? 'İşlem tamamlanamadı.' : _message,
                  style: const TextStyle(
                      color: AppTheme.statusWarning, fontSize: 13),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildActions() {
    switch (_state) {
      case _AiState.idle:
        return FilledButton.icon(
          onPressed: _capture,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          icon: const Icon(Icons.camera_alt_rounded),
          label: const Text('Fotoğraf Çek'),
        );
      case _AiState.captured:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _capture,
                child: const Text('Tekrar Çek'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _sendToAi,
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('AI\'a Gönder'),
              ),
            ),
          ],
        );
      case _AiState.sending:
        return const SizedBox.shrink();
      case _AiState.done:
        // Hizli akista geri sayim suruyorsa: buyuk "Dur" + kucuk "Şimdi Kaydet".
        if (_countdownMs > 0) {
          return Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelAutoAccept,
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('Dur'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _confirm,
                  child: const Text('Şimdi Kaydet'),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _capture,
                child: const Text('Tekrar Çek'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _confirm,
                child: const Text('Kullan'),
              ),
            ),
          ],
        );
      case _AiState.failed:
        return Column(
          children: [
            FilledButton.icon(
              onPressed: _capture,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tekrar Dene'),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _manual,
              icon: const Icon(Icons.keyboard_rounded, size: 18),
              label: const Text('Elle Gir'),
            ),
          ],
        );
    }
  }
}

/// ════════════════════════════════════════════════════════════════════
///  FOTOĞRAF ÇEK + ELLE GİR — gorme dostu manuel tarih girisi.
///  Buyuk foto onizleme + buyuk rakam girisi + otomatik nokta.
/// ════════════════════════════════════════════════════════════════════
class _DateInputFormatter extends TextInputFormatter {
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


/// ════════════════════════════════════════════════════════════════════
///  HIZLI TARİH GİRİŞİ — kamera ekranindan AYRILMADAN acilan alt sheet.
///
///  "Elle Gir" deyince kamera kapanmadan bu sheet acilir; klavye dogrudan
///  acilir, kullanici tarihi yazar (gg.aa.yyyy, otomatik nokta), "Devam Et"
///  ile o tarih dondurulur. Boylece form acilirken kamera kapanma + yeni
///  ekran + klavye ust uste yuklenmez; gecis akici olur (kasma cozuldu).
/// ════════════════════════════════════════════════════════════════════
class _QuickDateSheet extends StatefulWidget {
  const _QuickDateSheet();

  @override
  State<_QuickDateSheet> createState() => _QuickDateSheetState();
}

class _QuickDateSheetState extends State<_QuickDateSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Sheet acilir acilmaz klavyeyi ac.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime? _parse() => date_utils.DateUtils.parseManual(_ctrl.text);

  void _submit() {
    final date = _parse();
    if (date == null) {
      setState(() => _error =
          'Geçerli tarih girin. Örn: 15.03.27 veya sadece 03.27 (ay/yıl)');
      return;
    }
    Navigator.of(context).pop(date);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Son Kullanma Tarihi',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              inputFormatters: [_DateInputFormatter()],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'gg.aa.yyyy',
                hintStyle: TextStyle(
                    color: AppTheme.textTertiary, letterSpacing: 2),
                errorText: _error,
                filled: true,
                fillColor: AppTheme.background.withOpacity(0.4),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppTheme.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppTheme.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Devam Et',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
