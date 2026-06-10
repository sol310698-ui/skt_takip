import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_scalable_ocr/flutter_scalable_ocr.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;
import 'precise_scan_screen.dart';

/// Canli OCR islem hizi profilleri.
/// throttleMs dusuk + boxDivider buyuk = daha hizli/tepkisel ama daha cok
/// CPU/pil. Kullanici sag ustteki ayardan secer.
enum _ScanSpeed {
  fast,
  normal,
  battery;

  /// Iki isleme arasi minimum sure (ms). Dusuk = daha sik = daha hizli.
  int get throttleMs {
    switch (this) {
      case _ScanSpeed.fast:    return 250;
      case _ScanSpeed.normal:  return 450;
      case _ScanSpeed.battery: return 700;
    }
  }

  /// Oylama icin tutulan kare sayisi. Az = daha az is.
  int get maxRecentTexts {
    switch (this) {
      case _ScanSpeed.fast:    return 3;
      case _ScanSpeed.normal:  return 4;
      case _ScanSpeed.battery: return 5;
    }
  }

  /// Tarama kutusu yuksekligi boleni. Buyuk = dar serit = az piksel = hizli.
  double get boxDivider {
    switch (this) {
      case _ScanSpeed.fast:    return 3.5;
      case _ScanSpeed.normal:  return 3.0;
      case _ScanSpeed.battery: return 3.0;
    }
  }

  String get label {
    switch (this) {
      case _ScanSpeed.fast:    return 'Hızlı';
      case _ScanSpeed.normal:  return 'Normal';
      case _ScanSpeed.battery: return 'Pil Dostu';
    }
  }

  String get hint {
    switch (this) {
      case _ScanSpeed.fast:    return 'En tepkisel · daha çok pil';
      case _ScanSpeed.normal:  return 'Dengeli (önerilen)';
      case _ScanSpeed.battery: return 'Yavaş · pil tasarrufu';
    }
  }

  IconData get icon {
    switch (this) {
      case _ScanSpeed.fast:    return Icons.bolt_rounded;
      case _ScanSpeed.normal:  return Icons.speed_rounded;
      case _ScanSpeed.battery: return Icons.battery_saver_rounded;
    }
  }
}

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

  // Tarih okundugunda kamera bolgesinin yakalanmis goruntusu (kanit).
  final GlobalKey _captureKey = GlobalKey();
  Uint8List? _capturedFrame;

  DateTime _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);

  // Islem hizi - kullanici sag ustteki ayardan secer.
  // throttle dusuk = daha sik isleme = daha hizli ama daha cok CPU/pil.
  _ScanSpeed _speed = _ScanSpeed.normal;
  int get _throttleMs => _speed.throttleMs;

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
    // ScalableOCR kendi kamera kaynagini, agactan kaldirilinca birakir.
    // _ready=false yaparak widget'in kesin sokuldugunden emin ol.
    _ready = false;
    super.dispose();
  }

  // Son karelerin metinlerini biriktir (coklu kare oylamasi icin)
  final List<String> _recentTexts = [];
  int get _maxRecentTexts => _speed.maxRecentTexts;

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

    // 1) Tek karede cok guclu bir aday varsa hemen kabul et.
    final single = du.DateUtils.parseAllCandidates(value);
    if (single.isNotEmpty && single.first.score >= 80) {
      _accept(single.first.date);
      return;
    }

    // 2) Coklu kareden oylama: biriken tum karelerdeki adaylari skorla,
    // oylama bonusu uygulayip en guvenli adayi sec. Yeterince yuksek
    // (>=100) skora ulasinca kabul et. Bu, ardisik kararsiz okumalarda
    // erken/yanlis kabulu onler.
    final best = du.DateUtils.bestCandidateFromMultiple(_recentTexts);
    if (best == null) return;
    if (best.score >= 100) {
      _accept(best.date);
    }
  }

  void _accept(DateTime date) {
    // Once o anki kamera karesini yakala (kanit goruntusu), sonra sonucu goster.
    _captureFrame();
    setState(() {
      _detected = date;
      _done = true;
    });
  }

  /// RepaintBoundary'den o anki kamera bolgesinin PNG goruntusunu alir.
  Future<void> _captureFrame() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null && mounted) {
        setState(() => _capturedFrame = byteData.buffer.asUint8List());
      }
    } catch (_) {
      // Yakalama basarisiz olursa sessizce gec; pencere foto'suz acilir.
    }
  }

  void _confirm() => Navigator.of(context).pop(_detected);
  void _manual() => Navigator.of(context).pop(DateTime(1900));

  /// Islem hizini degistir ve OCR'i yeni ayarla temiz yeniden kur.
  Future<void> _changeSpeed(_ScanSpeed s) async {
    if (s == _speed) return;
    setState(() {
      _speed = s;
      _recentTexts.clear();
      _lastProcess = DateTime.fromMillisecondsSinceEpoch(0);
      _ready = false;       // kamerayi kaldir
      _scanSession++;       // ScalableOCR'i yeni boxHeight ile yeniden kur
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem hızı: ${s.label}'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _ready = true);
  }

  /// Detayli (foto-cek + on isleme) moda gec. Sonuc gelirse onu dondur.
  Future<void> _openPrecise() async {
    final result = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(builder: (_) => const PreciseScanScreen()),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  /// AI ile oku - 3. kademe. Su an arayuz hazir, baglanti sonra kurulacak.
  /// Fotograf cekilir, "AI'a gonderiliyor" akisi gosterilir (placeholder).
  Future<void> _openAi() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AiScanSheet(),
    );
    if (picked != null && mounted) {
      Navigator.of(context).pop(picked);
    }
  }

  Future<void> _retry() async {
    // Kamerayi tamamen kapat, kisa bekle, temiz yeniden kur.
    setState(() {
      _detected = null;
      _done = false;
      _capturedFrame = null; // yakalanan kareyi temizle
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
        actions: [
          PopupMenuButton<_ScanSpeed>(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'İşlem Hızı',
            color: AppTheme.surfaceHigh,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            onSelected: _changeSpeed,
            itemBuilder: (_) => _ScanSpeed.values.map((s) {
              final selected = s == _speed;
              return PopupMenuItem<_ScanSpeed>(
                value: s,
                child: Row(
                  children: [
                    Icon(s.icon,
                        size: 18,
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.label,
                              style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.textPrimary)),
                          Text(s.hint,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary)),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_rounded,
                          size: 16, color: AppTheme.primary),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
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
              child: RepaintBoundary(
                key: _captureKey,
                child: ScalableOCR(
                  key: ValueKey('ocr_$_scanSession'),
                  // Kutu cizimi YOK: kullanici cerceve gormez,
                  // kameradaki metin serbestce taranir.
                  paintboxCustom: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 0
                    ..color = Colors.transparent,
                  boxLeftOff: 1,
                  boxBottomOff: 1.5,
                  boxRightOff: 1,
                  boxTopOff: 1.5,
                  boxHeight: MediaQuery.of(context).size.height /
                      _speed.boxDivider,
                  getScannedText: _onScannedText,
                ),
              ),
            ),
          if (_ready) _buildHint(),
          if (_ready && !_done) _buildActionBar(),
          if (_done) _buildResultSheet(),
        ],
      ),
    );
  }

  Widget _buildHint() {
    if (_done) return const SizedBox.shrink();
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.14,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
      ),
    );
  }

  /// Alt sabit aksiyon cubugu: kademeli tarama secenekleri (manuel gecis).
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
              const Text(
                'Otomatik okumuyor mu?',
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // 2. kademe: detayli tarama (foto-cek + on isleme)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openPrecise,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.center_focus_strong_rounded,
                          size: 18),
                      label: const Text('Detaylı Tara',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 3. kademe: AI ile oku
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openAi,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent.withOpacity(0.2),
                        foregroundColor: AppTheme.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text('AI ile Oku',
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
            // Yakalanan kamera karesi - kullanici tarihi gozle dogrulasin.
            if (_capturedFrame != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                child: Image.memory(
                  _capturedFrame!,
                  width: double.infinity,
                  height: 130,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Okunan görüntü — tarihi doğrulayın',
                  style: TextStyle(
                      color: AppTheme.textTertiary, fontSize: 12)),
              const SizedBox(height: 14),
            ],
            Icon(
              _capturedFrame != null
                  ? Icons.fact_check_rounded
                  : Icons.check_circle_rounded,
              color: AppTheme.statusSafe,
              size: _capturedFrame != null ? 36 : 52,
            ),
            const SizedBox(height: 8),
            const Text('Tarih Bulundu',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            Text(dateStr,
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.statusSafe)),
            const SizedBox(height: 20),
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

/// 3. kademe: "AI ile Oku" kayan penceresi.
/// Su an arayuz hazir; gercek AI cagrisi henuz baglanmadi.
/// Akis: fotograf cek -> "AI'a gonderiliyor" gorunumu -> (placeholder)
/// sonuc / elle giris. AI baglaninca sadece _sendToAi doldurulacak.
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
