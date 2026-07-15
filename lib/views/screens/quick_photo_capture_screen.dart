import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/camera_helper.dart';
import '../../core/theme/app_theme.dart';

/// ════════════════════════════════════════════════════════════════════
///  UYGULAMA ICI HIZLI FOTOGRAF CEKIMI (SISTEM KAMERASINI ACMADAN)
/// ────────────────────────────────────────────────────────────────────
///  Neden ayri bir ekran? image_picker cagrisi telefonun KAMERA UYGULAMASINI
///  acar; bu uygulamayi arka plana atar, pil tuketir, yavaslatir ve donuste
///  akisi bozar. Bunun yerine burada `camera` paketiyle uygulama ICINDE bir
///  onizleme acilir, ~1 sn geri sayimdan sonra OTOMATIK cekim yapilir.
///
///  Akis:
///    1) Kamera onizlemesi acilir (arka kamera, sessiz).
///    2) 1 sn geri sayim (halka animasyonu). Kullanici isterse "Şimdi çek"
///       ile erken cekebilir ya da X ile vazgecebilir.
///    3) Cekim yapilir, foto 720 px'e kucultulur.
///    4) Kisa bir onizleme: 2,5 sn icinde dokunulmazsa OTOMATIK "Kullan"
///       (akis hizli olsun). "Tekrar çek" ile yeniden denenir.
///    5) Ekran, kucultulmus KALICI dosya yolunu geri dondurur (iptalde null).
///
///  Bu ekran fotografi HICBIR veritabanina yazmaz; sadece dosya yolunu
///  dondurur. Cagiran taraf (orn. Fiyat Kontrol) donen yolu barkod dizinine
///  (ortak yerel veritabani) kaydeder; boylece foto uygulamanin her yerinde
///  internet olmadan da gorunur.
/// ════════════════════════════════════════════════════════════════════
class QuickPhotoCaptureScreen extends StatefulWidget {
  /// Ust seritte gosterilecek urun adi (bilgilendirme icin).
  final String? productName;

  /// Ust seritte gosterilecek barkod (bilgilendirme icin).
  final String? barcode;

  /// Otomatik cekime kadar geri sayim suresi.
  final Duration countdown;

  /// Cekilen fotografin en uzun kenari (px). Varsayilan 720.
  final int maxSide;

  const QuickPhotoCaptureScreen({
    super.key,
    this.productName,
    this.barcode,
    this.countdown = const Duration(seconds: 1),
    this.maxSide = 720,
  });

  @override
  State<QuickPhotoCaptureScreen> createState() =>
      _QuickPhotoCaptureScreenState();
}

class _QuickPhotoCaptureScreenState extends State<QuickPhotoCaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cam;
  bool _initializing = true;
  bool _initError = false;
  bool _capturing = false;

  /// Cekildikten sonra onizlenen (henuz kucultulmemis) gecici dosya yolu.
  String? _shotPath;

  /// Cekimden sonra otomatik "Kullan" icin sayac.
  Timer? _autoUseTimer;

  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(vsync: this, duration: widget.countdown);
    _initCamera();
  }

  @override
  void dispose() {
    _autoUseTimer?.cancel();
    _ring.dispose();
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() {
          _initializing = false;
          _initError = true;
        });
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium, // 720p civari — kucuk foto icin yeterli
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cam = controller;
        _initializing = false;
      });
      // Geri sayimi baslat; bitince otomatik cek.
      _ring.forward(from: 0);
      _autoUseTimer = Timer(widget.countdown, () {
        if (mounted && _shotPath == null) _capture();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _initError = true;
        });
      }
    }
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _capturing || _shotPath != null) return;
    setState(() => _capturing = true);
    _ring.stop();
    _autoUseTimer?.cancel();
    HapticFeedback.mediumImpact();
    try {
      final file = await cam.takePicture();
      if (!mounted) return;
      setState(() {
        _shotPath = file.path;
        _capturing = false;
      });
      // Onizleme penceresi: 2,5 sn icinde dokunulmazsa otomatik kullan.
      _autoUseTimer = Timer(const Duration(milliseconds: 2500), _use);
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() {
    _autoUseTimer?.cancel();
    setState(() => _shotPath = null);
    _ring.forward(from: 0);
    _autoUseTimer = Timer(widget.countdown, () {
      if (mounted && _shotPath == null) _capture();
    });
  }

  Future<void> _use() async {
    _autoUseTimer?.cancel();
    final shot = _shotPath;
    if (shot == null) return;
    // Kucult + kalici dizine yaz, yolu dondur.
    String? finalPath;
    try {
      finalPath = await CameraHelper.downscaleToFile(
        shot,
        maxSide: widget.maxSide,
        quality: 80,
        subdir: 'product_photos',
      );
    } catch (_) {
      finalPath = shot; // en kotu ihtimal ham dosyayi dondur
    }
    if (!mounted) return;
    Navigator.of(context).pop(finalPath);
  }

  void _cancel() {
    _autoUseTimer?.cancel();
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _body()),

            // ── Ust serit: urun bilgisi + kapat ──
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ürün fotoğrafı çekiliyor',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            widget.productName?.trim().isNotEmpty == true
                                ? widget.productName!.trim()
                                : (widget.barcode ?? 'Ürün'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.black.withOpacity(0.55),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: _cancel,
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // ── Alt kontrol ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_initError || _cam == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded,
                  color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Kamera açılamadı',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _cancel, child: const Text('Kapat')),
            ],
          ),
        ),
      );
    }

    // Cekilen foto onizlemesi.
    if (_shotPath != null) {
      return Center(child: Image.file(File(_shotPath!), fit: BoxFit.contain));
    }

    // Canli kamera onizlemesi.
    return Center(child: CameraPreview(_cam!));
  }

  Widget _controls() {
    // Cekim sonrasi: Tekrar / Kullan.
    if (_shotPath != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _pill(
            icon: Icons.replay_rounded,
            label: 'Tekrar çek',
            onTap: _retake,
            bg: Colors.black54,
            fg: Colors.white,
          ),
          const SizedBox(width: 14),
          _pill(
            icon: Icons.check_rounded,
            label: 'Kullan',
            onTap: _use,
            bg: AppTheme.statusSafe,
            fg: Colors.white,
          ),
        ],
      );
    }

    // Cekimden once: geri sayim halkasi + "Şimdi çek".
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _capture,
          child: SizedBox(
            width: 78,
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _ring,
                  builder: (_, __) => SizedBox(
                    width: 78,
                    height: 78,
                    child: CircularProgressIndicator(
                      value: 1.0 - _ring.value,
                      strokeWidth: 5,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(
                          AppTheme.accent),
                    ),
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: _capturing ? Colors.white54 : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.black,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _capturing ? 'Çekiliyor…' : 'Otomatik çekiliyor — dokunarak hemen çek',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color bg,
    required Color fg,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
