import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// ════════════════════════════════════════════════════════════════════
///  DAYANIKLI TARAYICI (ResilientScanner)
/// ────────────────────────────────────────────────────────────────────
///  Sorun: mobile_scanner controller'i, kamerayi ELE GECIREMEDIGINDE
///  (ornegin ayni tarama sayfasi HIZLICA arka arkaya acildiginda; onceki
///  sayfanin kamerasi donanimda henuz serbest kalmamistir) "hata"
///  durumuna duser ve ekranda UNLEM gosterir. Bu durumdaki bir controller
///  `start()` ile CANLANMAZ — icsel durumu bozuktur. Tek guvenilir kurtarma
///  controller'i TAMAMEN atip (dispose) YENIDEN YARATMAKTIR.
///
///  Bu widget controller'in TUM yasam dongusunu kendi ustlenir:
///    • initState'te controller'i [create] ile yaratir,
///    • kamera hataya duserse controller'i dispose edip yenisini yaratir
///      (artan gecikmeyle birkac kez; sonra elle "Tekrar dene"),
///    • uygulama arka plana gidince durdurur, one donunce YENIDEN YARATIR,
///    • dispose'ta controller'i birakir.
///
///  Ekran, olusturulan canli controller'a (flas/tors gibi islemler icin)
///  [onReady] ile erisir. Controller her yeniden yaratildiginda [onReady]
///  tekrar cagrilir; ekran referansini guncel tutsun.
///
///  Kullanan ekran AYRICA CameraLifecycleMixin KULLANMAMALI ve controller'i
///  KENDI dispose ETMEMELI — ikisini de bu widget yapar (cift dispose /
///  cift yasam dongusu cakismasi olmasin).
/// ════════════════════════════════════════════════════════════════════
class ResilientScanner extends StatefulWidget {
  /// Controller fabrikasi. Her (yeniden) yaratimda cagrilir; DAIMA YENI bir
  /// [MobileScannerController] dondurmeli (ayni ornegi tekrar dondurmeyin).
  final MobileScannerController Function() create;

  /// Barkod okundugunda cagrilir.
  final void Function(BarcodeCapture) onDetect;

  /// Canli controller olustugunda/degistiginde bildirilir (flas vb. icin).
  final ValueChanged<MobileScannerController>? onReady;

  /// Kamera onizleme sigdirma bicimi.
  final BoxFit fit;

  /// Hata/hazirlik ekraninin vurgu rengi.
  final Color accent;

  const ResilientScanner({
    super.key,
    required this.create,
    required this.onDetect,
    this.onReady,
    this.fit = BoxFit.cover,
    this.accent = const Color(0xFF1E9E52),
  });

  @override
  State<ResilientScanner> createState() => _ResilientScannerState();
}

class _ResilientScannerState extends State<ResilientScanner>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  Timer? _timer;
  bool _recovering = false;
  int _errAttempt = 0;
  // Hata sonrasi otomatik denemeler bittiyse elle butonu goster.
  static const int _maxAutoAttempts = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spawn();
  }

  void _spawn() {
    final c = widget.create();
    _controller = c;
    widget.onReady?.call(c);
  }

  /// Controller'i dispose edip yenisini yaratir (yaris korumali). Onizlemeyi
  /// once tamamen sokup (setState _controller=null) kisa bir gecikmeyle yeni
  /// controller kurar; boylece donanim serbest kalir.
  Future<void> _recreate() async {
    if (_recovering || !mounted) return;
    _recovering = true;
    final old = _controller;
    if (mounted) setState(() => _controller = null);
    try {
      await old?.dispose();
    } catch (_) {}
    // Onceki kamera donanimda serbest kalsin diye kisa bekleme.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      _recovering = false;
      return;
    }
    setState(_spawn);
    _recovering = false;
  }

  /// errorBuilder icinden cagrilir: bozuk controller'i yeniden yaratmayi
  /// planla (artan gecikme). Denemeler tukenirse elle butona birak.
  void _scheduleErrorRecreate() {
    if (_recovering || _timer != null) return;
    if (_errAttempt >= _maxAutoAttempts) return;
    _errAttempt++;
    _timer = Timer(Duration(milliseconds: 300 * _errAttempt), () {
      _timer = null;
      _recreate();
    });
  }

  void _manualRetry() {
    _timer?.cancel();
    _timer = null;
    _errAttempt = 0;
    _recreate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // One donunce controller'i TAZELE (start() yerine yeniden yarat;
      // arka planda kamera baska surec tarafindan alinmis olabilir).
      _errAttempt = 0;
      _recreate();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      try {
        _controller?.stop();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return _Preparing(accent: widget.accent);
    }
    return MobileScanner(
      controller: c,
      onDetect: widget.onDetect,
      fit: widget.fit,
      errorBuilder: (context, error, child) {
        // Hata durumunda otomatik yeniden-yaratmayi planla (build sirasinda
        // setState yapmadan; Timer bir sonraki frame'de calisir).
        _scheduleErrorRecreate();
        return _Preparing(
          accent: widget.accent,
          onRetry: _errAttempt >= _maxAutoAttempts ? _manualRetry : null,
        );
      },
    );
  }
}

/// Kamera hazirlanirken/hatasinda gosterilen sade ekran.
class _Preparing extends StatelessWidget {
  final Color accent;
  final VoidCallback? onRetry;
  const _Preparing({required this.accent, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
          ),
          const SizedBox(height: 14),
          const Text('Kamera hazırlanıyor…',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Kamera bir önceki ekrandan serbest bırakılıyor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tekrar dene'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
