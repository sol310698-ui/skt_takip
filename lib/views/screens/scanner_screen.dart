import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
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

  /// Fotograf cek: tam ekran sayfada yatay goster, kullanici tarihi girsin.
  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    if (c.value.isTakingPicture) return;
    setState(() => _capturing = true);
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      final cropped = await _cropCenterBand(bytes);
      if (!mounted) return;
      setState(() => _capturing = false);

      // Foto ekrani acilirken kamerayi kapat (kaynak/pil tasarrufu).
      await _controller?.dispose();
      _controller = null;
      if (mounted) setState(() {});

      // Tam ekran sayfa: yatay foto + tarih girisi.
      final result = await Navigator.of(context).push<DateTime>(
        MaterialPageRoute(
          builder: (_) => _PhotoDateScreen(photo: cropped ?? bytes),
        ),
      );
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(result);
      } else {
        // Iptal: foto ekranindan dönüldü, kamerayi yeniden baslat.
        await _initCamera();
      }
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Cekilen foto'nun MERKEZ yatay bandini kirpar (cerceveye denk gelen yer).
  /// Cerceve ekranda yatay genis bir bant; foto'nun ortasini alir.
  Future<Uint8List?> _cropCenterBand(Uint8List jpeg) async {
    try {
      final decoded = img.decodeImage(jpeg);
      if (decoded == null) return null;
      // EXIF yonelimini duzelt (telefon foto'lari donuk gelebilir).
      final oriented = img.bakeOrientation(decoded);
      final w = oriented.width;
      final h = oriented.height;

      // Cerceve orani: ekranda genislik %96, yukseklik genisligin %50'si.
      // Foto'da: tam genislik, ortada o orana denk yukseklikte bant.
      // Biraz pay birak (tarih + ust/alt satir icin).
      final bandH = (w * 0.62).round().clamp(1, h); // yatay bant yuksekligi
      final top = ((h - bandH) / 2).round().clamp(0, h - 1);

      final cropped = img.copyCrop(
        oriented,
        x: 0,
        y: top,
        width: w,
        height: bandH,
      );
      return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
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
///  FOTOĞRAF + TARİH — tam ekran sayfa.
///  Ust: cekilen foto YATAY (alt kismi sola gelecek sekilde 90° donuk),
///       buyuk, yakinlastirilabilir.
///  Alt: "Devam" -> tarih giris alani + Tamamla.
/// ════════════════════════════════════════════════════════════════════
class _PhotoDateScreen extends StatefulWidget {
  final Uint8List photo;
  const _PhotoDateScreen({required this.photo});

  @override
  State<_PhotoDateScreen> createState() => _PhotoDateScreenState();
}

class _PhotoDateScreenState extends State<_PhotoDateScreen> {
  final _ctrl = TextEditingController();
  final TransformationController _tc = TransformationController();
  DateTime? _parsed;
  bool _entering = false; // false: foto+Devam, true: tarih girisi
  double _zoom = 1.0;
  static const List<double> _zoomLevels = [1, 2, 3, 4];

  @override
  void dispose() {
    _ctrl.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _setZoom(double z) {
    setState(() => _zoom = z);
    // Merkezden zoom uygula.
    _tc.value = Matrix4.identity()..scale(z);
  }

  void _parse() {
    final txt = _ctrl.text.trim();
    DateTime? d;
    try {
      final p = txt.split('.');
      if (p.length == 3 && p[2].length == 4) {
        d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    setState(() => _parsed = d);
  }

  void _confirm() {
    if (_parsed != null) Navigator.of(context).pop(_parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Tarihi Gir'),
        actions: [
          // Sag ustte zoom secici (1x / 2x / 3x / 4x)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: _zoomLevels.map((z) {
                final active = _zoom == z;
                return GestureDetector(
                  onTap: () => _setZoom(z),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.primary
                          : Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${z.toInt()}x',
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Foto: yatay (alt kismi sola), buyuk, yakinlastirilabilir ──
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  transformationController: _tc,
                  minScale: 1,
                  maxScale: 6,
                  onInteractionEnd: (_) {
                    // Pinch ile degisen zoom'u butonlara yansit.
                    final s = _tc.value.getMaxScaleOnAxis();
                    if ((s - _zoom).abs() > 0.05) {
                      setState(() => _zoom = s);
                    }
                  },
                  child: RotatedBox(
                    quarterTurns: 3, // alt kisim sola (saat tersi 90°)
                    child: Image.memory(
                      widget.photo,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Alt panel ──
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: SafeArea(
              top: false,
              child: !_entering
                  ? _buildContinue()
                  : _buildDateEntry(),
            ),
          ),
        ],
      ),
    );
  }

  // 1. asama: foto goster, "Devam" ile tarih girisine gec.
  Widget _buildContinue() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.zoom_in_rounded,
                size: 16, color: AppTheme.textTertiary),
            SizedBox(width: 6),
            Text('Tarihi görmek için iki parmakla büyüt',
                style: TextStyle(
                    color: AppTheme.textTertiary, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(() => _entering = true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text('Devam',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  // 2. asama: tarih girisi + tamamla.
  Widget _buildDateEntry() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [_DateInputFormatter()],
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
          onChanged: (_) => _parse(),
          decoration: InputDecoration(
            hintText: 'GG.AA.YYYY',
            hintStyle: TextStyle(
              fontSize: 22,
              color: AppTheme.textTertiary.withOpacity(0.5),
              letterSpacing: 1.5,
            ),
            filled: true,
            fillColor: AppTheme.surfaceAlt,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
          ),
        ),
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
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _parsed != null ? _confirm : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.statusSafe,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Tamamla',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}
