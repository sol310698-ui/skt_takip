import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scalable_ocr/flutter_scalable_ocr.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;

/// Canli SKT tarama. Karasizlik cozumu:
/// - Widget'i acip kapamak yerine hep acik tut (kamera cakismasi olmasin)
/// - Her yeni taramada ValueKey degistir (eski veri/state sifirlanir)
/// - Throttle (buffer dolmasin)
/// - _done iken islemeyi durdur ama kamerayi yok etme
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // Her sifirlamada degisir -> ScalableOCR tamamen yeniden kurulur (stale fix)
  int _scanSession = 0;

  DateTime? _detected;
  bool _done = false;

  // En son okunan ham metin - tarih bu turda mi okundu kontrolu icin
  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttleMs = 600;

  // Ayni tarihi ust uste dogrulama: 2 kez ayni cikinca kabul et (yanlis pozitif azalt)
  DateTime? _pendingDate;
  int _pendingCount = 0;

  @override
  void dispose() {
    super.dispose();
  }

  void _onScannedText(String value) {
    if (_done) return;

    final now = DateTime.now();
    if (now.difference(_lastProcess).inMilliseconds < _throttleMs) return;
    _lastProcess = now;

    final date = du.DateUtils.parseFromOcr(value);
    if (date == null) return;

    // Ayni tarih 2 kez ust uste okunursa kabul et (kararlilik).
    if (_pendingDate != null && _pendingDate!.isAtSameMomentAs(date)) {
      _pendingCount++;
    } else {
      _pendingDate = date;
      _pendingCount = 1;
    }

    if (_pendingCount >= 2) {
      setState(() {
        _detected = date;
        _done = true;
      });
    }
  }

  void _confirm() => Navigator.of(context).pop(_detected);
  void _manual() => Navigator.of(context).pop(DateTime(1900));

  void _retry() {
    setState(() {
      _detected = null;
      _done = false;
      _pendingDate = null;
      _pendingCount = 0;
      _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
      _scanSession++; // ScalableOCR'i tamamen sifirla (eski veri temizlenir)
    });
  }

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
          // Kamera hep acik. _done iken sadece islemiyoruz.
          // ValueKey ile her session'da temiz kurulum.
          Center(
            child: ScalableOCR(
              key: ValueKey('ocr_$_scanSession'),
              paintboxCustom: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 4.0
                ..color = _done
                    ? AppTheme.statusSafe
                    : AppTheme.primary,
              boxLeftOff: 4,
              boxBottomOff: 2.8,
              boxRightOff: 4,
              boxTopOff: 2.8,
              boxHeight: MediaQuery.of(context).size.height / 3.5,
              getScannedText: _onScannedText,
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
