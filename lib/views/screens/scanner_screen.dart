import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scalable_ocr/flutter_scalable_ocr.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;
import 'precise_scan_screen.dart';

/// Canli SKT tarama. Karasizlik cozumu:
/// - Acilista once kamera iznini al + kisa isitma gecikmesi (kasma fix)
/// - Her yeni taramada ValueKey degistir (eski veri/state sifirlanir)
/// - Throttle (buffer dolmasin)
/// - Cift dogrulama (yanlis pozitif/eski veri azalt)
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // Her sifirlamada degisir -> ScalableOCR tamamen yeniden kurulur (stale fix)
  int _scanSession = 0;

  bool _ready = false;

  DateTime? _detected;
  bool _done = false;

  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
  static const _throttleMs = 600;

  DateTime? _pendingDate;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// Kamera hazirlanmasi icin kisa gecikme, sonra OCR baslatilir.
  Future<void> _prepare() async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Son karelerin metinlerini biriktir (coklu kare oylamasi icin)
  final List<String> _recentTexts = [];
  static const _maxRecentTexts = 4;

  void _onScannedText(String value) {
    if (_done) return;

    final now = DateTime.now();
    if (now.difference(_lastProcess).inMilliseconds < _throttleMs) return;
    _lastProcess = now;

    if (value.trim().isEmpty) return;

    // Son kareleri biriktir.
    _recentTexts.add(value);
    if (_recentTexts.length > _maxRecentTexts) {
      _recentTexts.removeAt(0);
    }

    // Once tek karede guclu bir aday var mi bak (hizli yakalama).
    final single = du.DateUtils.parseAllCandidates(value);
    if (single.isNotEmpty && single.first.score >= 80) {
      // Yuksek guvenli tek okuma - hemen kabul (cift dogrulamaya gerek yok).
      _accept(single.first.date);
      return;
    }

    // Coklu kareden oylama (tek kare zayifsa birikimle karar ver).
    final voted = du.DateUtils.parseFromMultiple(_recentTexts);
    if (voted == null) return;

    // Oylanan tarih son 2 karede tutarli mi?
    if (_pendingDate != null && _pendingDate!.isAtSameMomentAs(voted)) {
      _pendingCount++;
    } else {
      _pendingDate = voted;
      _pendingCount = 1;
    }
    if (_pendingCount >= 2) {
      _accept(voted);
    }
  }

  void _accept(DateTime date) {
    setState(() {
      _detected = date;
      _done = true;
    });
  }

  void _confirm() => Navigator.of(context).pop(_detected);
  void _manual() => Navigator.of(context).pop(DateTime(1900));

  /// Hassas (foto-cek + on isleme) moda gec. Sonuc gelirse onu dondur.
  Future<void> _openPrecise() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const PreciseScanScreen()),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _retry() async {
    // Kamerayi tamamen kapat, kisa bekle, temiz yeniden kur.
    setState(() {
      _detected = null;
      _done = false;
      _pendingDate = null;
      _pendingCount = 0;
      _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
      _recentTexts.clear(); // eski kare metinlerini temizle
      _ready = false; // kamerayi kaldir (gri kalmayi onler)
      _scanSession++; // ScalableOCR'i tamamen sifirla (eski veri temizlenir)
    });
    // Kamera donaniminin serbest kalmasi icin bekle, sonra yeniden kur.
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) setState(() => _ready = true);
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
          // Hazir degilse yukleniyor
          if (!_ready)
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
            )
          // Hazir: OCR kamerasi
          else
            Center(
              child: ScalableOCR(
                key: ValueKey('ocr_$_scanSession'),
                paintboxCustom: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 4.0
                  ..color = _done ? AppTheme.statusSafe : AppTheme.primary,
                boxLeftOff: 5,
                boxBottomOff: 2.5,
                boxRightOff: 5,
                boxTopOff: 2.5,
                boxHeight: MediaQuery.of(context).size.height / 3,
                getScannedText: _onScannedText,
              ),
            ),
          if (_ready) _buildHint(),
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
          // Zor etiket icin hassas (foto-cek) moda gec
          FilledButton.icon(
            onPressed: _openPrecise,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            icon: const Icon(Icons.center_focus_strong_rounded,
                color: Colors.white, size: 18),
            label: const Text('Zor okunuyor? Hassas Tara',
                style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 6),
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
