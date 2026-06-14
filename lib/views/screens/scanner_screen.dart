import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  SKT TARA — basit, gorme dostu manuel tarih okuma ekrani.
///
///  Akis: kamera canli onizleme -> kullanici tarihi cerceveye getirir ->
///  "Fotograf Cek" -> cerceve ici kirpilir, buyutulur -> kullanici tarihi
///  elle girer. Otomatik OCR YOK (donma/karmaşa kaynagiydi).
///
///  Kamera yonetimi tamamen "camera" paketi ile, net yasam dongusu:
///  initState -> init, dispose -> birak, app arka plan -> duraklat/devam.
/// ════════════════════════════════════════════════════════════════════
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _capturing = false;
  bool _torchOn = false;
  final GlobalKey _previewKey = GlobalKey();

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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      c.dispose();
      _controller = null;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
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
      _initFuture = controller.initialize();
      await _initFuture;
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      // Kamera acilamadi — kullanici elle girebilir.
    }
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

  /// Fotograf cek: cerceve ici bolgeyi kirp, buyut, manuel giris penceresi ac.
  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    if (c.value.isTakingPicture) return;
    setState(() => _capturing = true);
    try {
      // Flas durumunu koru, net cekim icin odaklan.
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      final cropped = await _cropToFrame(bytes);
      if (!mounted) return;
      setState(() => _capturing = false);

      final result = await showModalBottomSheet<DateTime>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ManualCaptureSheet(frame: cropped ?? bytes),
      );
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
      }
      // Iptal: kamera zaten canli, ekstra is gerekmez.
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Cekilen tam foto'dan, ekrandaki cerceveye denk gelen orta bandi kirpar.
  /// Cerceve: yatay %90, dikey orta ~%30 (tarih satiri icin yeterli).
  Future<Uint8List?> _cropToFrame(Uint8List jpeg) async {
    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width.toDouble();
      final h = img.height.toDouble();

      // Cerceve oranlari (onizlemedeki kutuyla uyumlu).
      // Cerceve oranlari — dar tut ki tarih buyuk gorunsun.
      const hFrac = 0.8; // yatay %80
      const vFrac = 0.22; // dikey %22 (dar bant = daha buyuk tarih)
      final cropW = w * hFrac;
      final cropH = h * vFrac;
      final cropL = (w - cropW) / 2;
      final cropT = (h - cropH) / 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final src = Rect.fromLTWH(cropL, cropT, cropW, cropH);
      final dst = Rect.fromLTWH(0, 0, cropW, cropH);
      canvas.drawImageRect(img, src, dst, Paint());
      final pic = recorder.endRecording();
      final out = await pic.toImage(cropW.round(), cropH.round());
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _manual() => Navigator.of(context).pop(DateTime(1900));

  Future<void> _openAi() async {
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AiScanSheet(),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('SKT Tara'),
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

          // ── Ust ipucu ──
          if (ready)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.13,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Son kullanma tarihini çerçeveye getirin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),

          // ── Alt aksiyon cubugu ──
          if (ready) _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Foto cek + elle gir (gorme dostu ana akis)
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: _capturing ? null : _capture,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _capturing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.photo_camera_rounded, size: 20),
                      label: Text(_capturing ? 'Çekiliyor...' : 'Fotoğraf Çek',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // AI ile oku
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _openAi,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent.withOpacity(0.2),
                        foregroundColor: AppTheme.accent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('AI',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _manual,
                icon: const Icon(Icons.keyboard_rounded,
                    color: AppTheme.textSecondary, size: 18),
                label: const Text('Elle gir',
                    style: TextStyle(color: AppTheme.textSecondary)),
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
  const _AiScanSheet();

  @override
  State<_AiScanSheet> createState() => _AiScanSheetState();
}

class _AiScanSheetState extends State<_AiScanSheet> {
  _AiState _state = _AiState.idle;
  String? _photoPath;
  DateTime? _result;
  String _message = '';

  Future<void> _capture() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (photo == null) return;
      setState(() {
        _photoPath = photo.path;
        _state = _AiState.captured;
      });
    } catch (e) {
      setState(() {
        _state = _AiState.failed;
        _message = 'Fotoğraf alınamadı: $e';
      });
    }
  }

  /// AI'a gonderme - PLACEHOLDER.
  /// TODO(ai): Burada cekilen fotograf (_photoPath) AI servisine gonderilip
  /// donen tarih _result'a yazilacak. Su an baglanti yok.
  Future<void> _sendToAi() async {
    if (_photoPath == null) return;
    setState(() {
      _state = _AiState.sending;
      _message = '';
    });

    // Simulasyon: kisa bir bekleme, ardindan "henuz baglanmadi" durumu.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // AI baglanti kurulmadigi icin simdilik basarisiz dur.
    setState(() {
      _state = _AiState.failed;
      _message =
          'AI okuma yakında aktif olacak. Şimdilik "Detaylı Tara" veya '
          'elle giriş kullanabilirsiniz.';
    });
  }

  void _confirm() {
    if (_result != null) Navigator.of(context).pop(_result);
  }

  void _manual() => Navigator.of(context).pop(DateTime(1900));

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
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
        return const Text(
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
            const Text('Fotoğraf hazır. AI\'a göndermek için dokunun.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        );
      case _AiState.sending:
        return const Column(
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
            const Text('AI Sonucu',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            Text(s,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.statusSafe)),
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
class _ManualCaptureSheet extends StatefulWidget {
  final Uint8List? frame;
  const _ManualCaptureSheet({this.frame});

  @override
  State<_ManualCaptureSheet> createState() => _ManualCaptureSheetState();
}

class _ManualCaptureSheetState extends State<_ManualCaptureSheet> {
  final _ctrl = TextEditingController();
  DateTime? _parsed;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _parse() {
    final txt = _ctrl.text.trim();
    DateTime? d;
    try {
      final p = txt.split('.');
      if (p.length == 3 && p[2].length == 4) {
        d = DateTime(
            int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    setState(() => _parsed = d);
  }

  void _confirm() {
    if (_parsed != null) Navigator.of(context).pop(_parsed);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tutamac
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Foto onizleme — 90° dik cevrilmis, buyuk, yakinlastirilabilir
              if (widget.frame != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.primary.withOpacity(0.5), width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.42,
                      width: double.infinity,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 6,
                        child: RotatedBox(
                          quarterTurns: 1, // 90° dik
                          child: Image.memory(
                            widget.frame!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Fotoğraf alınamadı',
                      style: TextStyle(color: AppTheme.textTertiary)),
                ),
              if (widget.frame != null) ...[
                const SizedBox(height: 6),
                const Text('İki parmakla büyütebilirsin',
                    style: TextStyle(
                        color: AppTheme.textTertiary, fontSize: 12)),
              ],
              const SizedBox(height: 14),

              // Kompakt tarih girisi (kullanici ne yazdigini biliyor)
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [_DateInputFormatter()],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
                onChanged: (_) => _parse(),
                decoration: InputDecoration(
                  hintText: 'GG.AA.YYYY',
                  hintStyle: TextStyle(
                    fontSize: 20,
                    color: AppTheme.textTertiary.withOpacity(0.5),
                    letterSpacing: 1.5,
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 2),
                  ),
                ),
              ),

              // Gecerli tarih onizleme
              const SizedBox(height: 10),
              AnimatedOpacity(
                opacity: _parsed != null ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.statusSafe, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _parsed != null
                          ? DateFormat('d MMMM yyyy', 'tr').format(_parsed!)
                          : '',
                      style: const TextStyle(
                        color: AppTheme.statusSafe,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Kompakt onay butonu
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _parsed != null ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.statusSafe,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Onayla',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Vazgeç',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kullanici sadece rakam girer, otomatik "gg.aa.yyyy" formatina sokar.
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
