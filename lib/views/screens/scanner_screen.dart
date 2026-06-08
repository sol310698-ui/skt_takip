import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scalable_ocr/flutter_scalable_ocr.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;

/// Canli SKT tarama - flutter_scalable_ocr ile.
/// Resmi ornek yapisina uygun (StreamController + GlobalKey) +
/// throttle (kasma/siyah ekran onlemek icin) + lifecycle yonetimi.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final StreamController<String> _controller = StreamController<String>();
  final GlobalKey<ScalableOCRState> _ocrKey = GlobalKey<ScalableOCRState>();

  DateTime? _detected;
  bool _done = false;
  bool _cameraAlive = true;

  // Throttle: cok sik islemeyi engelle (buffer dolmasin)
  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttleMs = 700;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.close();
    super.dispose();
  }

  /// Uygulama arka plana gidince kamerayi yok et, donunce yeniden kur.
  /// Bu, buffer birikimini ve siyah ekrani onler.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (mounted) setState(() => _cameraAlive = false);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && !_done) setState(() => _cameraAlive = true);
    }
  }

  void _onScannedText(String value) {
    if (_done) return;

    // Throttle: son islemden _throttleMs gecmediyse atla.
    final now = DateTime.now();
    if (now.difference(_lastProcess).inMilliseconds < _throttleMs) return;
    _lastProcess = now;

    _controller.add(value);
    final date = du.DateUtils.parseFromOcr(value);
    if (date != null) {
      setState(() {
        _detected = date;
        _done = true;
        _cameraAlive = false; // tarih bulundu, kamerayi durdur (buffer bosalt)
      });
    }
  }

  void _confirm() => Navigator.of(context).pop(_detected);
  void _manual() => Navigator.of(context).pop(DateTime(1900));
  void _retry() => setState(() {
        _detected = null;
        _done = false;
        _cameraAlive = true;
        _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('SKT Tara'),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Kamera sadece _cameraAlive iken kuruluyor (lifecycle + done)
          if (_cameraAlive)
            Center(
              child: ScalableOCR(
                key: _ocrKey,
                paintboxCustom: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 4.0
                  ..color = AppTheme.primary,
                boxLeftOff: 4,
                boxBottomOff: 2.8,
                boxRightOff: 4,
                boxTopOff: 2.8,
                boxHeight: MediaQuery.of(context).size.height / 3.5,
                getScannedText: _onScannedText,
              ),
            )
          else if (!_done)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 12),
                  Text('Kamera hazırlanıyor...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          _buildHint(),
          if (_done) _buildResultSheet(),
        ],
      ),
    );
  }

  Widget _buildHint() {
    if (_done) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.16,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.92),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Text(
              'Son kullanma tarihini çerçeveye getirin',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _manual,
            icon: const Icon(Icons.keyboard_rounded,
                color: Colors.white70, size: 18),
            label: const Text('Elle gir',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSheet() {
    final dateStr = DateFormat('dd.MM.yyyy').format(_detected!);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.statusSafe, size: 52),
            const SizedBox(height: 12),
            const Text('Tarih Bulundu',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            Text(dateStr,
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.statusSafe)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _retry,
                    child: const Text('Tekrar Tara'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirm,
                    child: const Text('Devam Et'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
