import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// ════════════════════════════════════════════════════════════════════
///  KAMERA HATA KURTARMA (mobile_scanner errorBuilder)
/// ────────────────────────────────────────────────────────────────────
///  mobile_scanner kamera hatasina dustugunde (ekranda UNLEM) gosterilir.
///  En sik neden: ayni tarayici sayfasi HIZLICA yeniden acildiginda onceki
///  ekranin kamerasi donanimda henuz serbest kalmamistir; yeni start() bu
///  yuzden basarisiz olup hata durumunda TAKILI kalir.
///
///  Bu widget, hatayi gorur gormez kamerayi OTOMATIK olarak (artan
///  gecikmeyle birkac kez) stop()+start() ile yeniden ele gecirmeyi dener;
///  boylece unlem kendiliginden gecer. Elle "Tekrar dene" de vardir.
/// ════════════════════════════════════════════════════════════════════
class ScanErrorRetry extends StatefulWidget {
  final MobileScannerController controller;
  const ScanErrorRetry({super.key, required this.controller});

  @override
  State<ScanErrorRetry> createState() => _ScanErrorRetryState();
}

class _ScanErrorRetryState extends State<ScanErrorRetry> {
  int _attempt = 0;
  bool _retrying = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Ilk hatada kisa gecikmeyle otomatik dene (onceki kamera serbest kalsin).
    _scheduleRetry(const Duration(milliseconds: 450));
  }

  void _scheduleRetry(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _retry);
  }

  Future<void> _retry() async {
    if (!mounted || _retrying) return;
    setState(() {
      _retrying = true;
      _attempt++;
    });
    try {
      await widget.controller.stop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    try {
      await widget.controller.start();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _retrying = false);
    // Start yine basarisizsa errorBuilder acik kalir; guvence icin birkac
    // kez daha (artan gecikmeyle) dene.
    if (_attempt < 5) {
      _scheduleRetry(Duration(milliseconds: 500 * (_attempt + 1)));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_retrying)
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          else
            const Icon(Icons.photo_camera_back_rounded,
                color: Colors.white70, size: 40),
          const SizedBox(height: 14),
          const Text('Kamera hazırlanıyor…',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Kamera bir önceki ekrandan serbest bırakılıyor olabilir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _retrying ? null : _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tekrar dene'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}
