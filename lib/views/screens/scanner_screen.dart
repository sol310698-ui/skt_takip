import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scalable_ocr/flutter_scalable_ocr.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_utils.dart' as du;

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

  // Sifirlamadan beri islenen kare sayisi (adaptif esik icin).
  int _framesSinceReset = 0;

  void _onScannedText(String value) {
    if (_done) return;

    final now = DateTime.now();
    if (now.difference(_lastProcess).inMilliseconds < _throttleMs) return;
    _lastProcess = now;

    if (value.trim().isEmpty) return;
    _framesSinceReset++;

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

    // 2) Coklu kareden oylama + ADAPTIF esik:
    // Ilk karelerde katiyiz (yanlis kabul olmasin); etiket zor okunuyorsa
    // (kare sayisi artiyor ama kabul yok) esigi kademeli dusur.
    // Dusuk esikler YALNIZCA gelecekteki tarihler icin gecerli —
    // gecmis tarihler (muhtemel uretim tarihi) hep yuksek esik ister.
    final best = du.DateUtils.bestCandidateFromMultiple(_recentTexts);
    if (best == null) return;

    final isFuture = du.DateUtils.daysUntil(best.date) >= 0;
    final int need;
    if (_framesSinceReset <= 3) {
      need = 100; // baslangic: katı
    } else if (_framesSinceReset <= 7) {
      need = isFuture ? 75 : 100; // zorlaniyor: biraz esnet
    } else {
      need = isFuture ? 55 : 90; // cok zorlaniyor: gelecek tarihe guven
    }

    if (best.score >= need) {
      _accept(best.date);
    }
  }

  void _accept(DateTime date) {
    // Kameranin hala ekranda oldugu bu anda frame'i yakala,
    // SONRA done=true yaparak kamerayi kapat.
    // (Eski: fire-and-forget cagri, widget kapaninca boundary null doner.)
    _captureAndAccept(date);
  }

  Future<void> _captureAndAccept(DateTime date) async {
    // Frame'i onceden yakala (kamera hala goruntuleniyor).
    await _captureFrame();
    if (!mounted) return;
    setState(() {
      _detected = date;
      _done = true;
    });
  }

  /// RepaintBoundary'den o anki kamera bolgesini yakalar, mavi tarama
  /// kutusunun ic bolgesini KIRPAR ve buyutur (gorme dostu okuma icin).
  Future<void> _captureFrame() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      const pr = 2.5; // yuksek cozunurluk yakala (buyutunce net kalsin)
      final full = await boundary.toImage(pixelRatio: pr);

      final fw = full.width.toDouble();
      final fh = full.height.toDouble();

      // Mavi kutunun widget icindeki oranlari:
      //  - yatay: kenarlardan %5'er off => orta %90
      //  - dikey: kutu yuksekligi = ekranYuksekligi / boxDivider,
      //           widget ortasinda konumlu.
      final screenH = MediaQuery.of(context).size.height;
      final widgetH = boundary.size.height; // ScalableOCR widget yuksekligi
      final boxH = screenH / _speed.boxDivider;
      // Kutu yuksekligi oraninu widget'a gore hesapla, biraz pay birak.
      var vFrac = (boxH / widgetH).clamp(0.12, 0.6);
      // Biraz dikey pay ekle (ust/alt yazi kesilmesin).
      vFrac = (vFrac * 1.6).clamp(0.12, 0.8);

      final cropW = fw * 0.9; // yatay %90
      final cropH = fh * vFrac;
      final cropL = fw * 0.05;
      final cropT = (fh - cropH) / 2; // dikey ortala

      // Kirpilan bolgeyi yeni bir image'a ciz.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final src = Rect.fromLTWH(cropL, cropT, cropW, cropH);
      final dst = Rect.fromLTWH(0, 0, cropW, cropH);
      canvas.drawImageRect(full, src, dst, Paint());
      final picture = recorder.endRecording();
      final cropped =
          await picture.toImage(cropW.round(), cropH.round());

      final byteData =
          await cropped.toByteData(format: ui.ImageByteFormat.png);
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
      _framesSinceReset = 0;
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

  /// Fotografi cek ve elle gir: cerceveki alanin fotosunu yakalar,
  /// buyuk gosterip kullanicidan tarihi manuel ister (gorme dostu akis).
  Future<void> _captureForManual() async {
    await _captureFrame();
    if (!mounted) return;
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManualCaptureSheet(frame: _capturedFrame),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      // Iptal: kamera/OCR donmus olabilir -> yeniden kur.
      setState(() {
        _capturedFrame = null;
        _scanSession++;
      });
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
      _framesSinceReset = 0;
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Kamera + OCR. paintbox saydam -> tespit kutulari ve
                  // cerceve YAKALANAN foto'ya karismaz.
                  RepaintBoundary(
                    key: _captureKey,
                    child: ScalableOCR(
                      key: ValueKey('ocr_$_scanSession'),
                      paintboxCustom: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 0.0
                        ..color = const Color(0x00000000), // tamamen saydam
                      boxLeftOff: 5,
                      boxBottomOff: 2.5,
                      boxRightOff: 5,
                      boxTopOff: 2.5,
                      boxHeight: MediaQuery.of(context).size.height /
                          _speed.boxDivider,
                      getScannedText: _onScannedText,
                    ),
                  ),
                  // Kendi cercevemiz — sadece ekranda gorunur, foto'ya girmez
                  // (RepaintBoundary'nin disinda).
                  IgnorePointer(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      height: MediaQuery.of(context).size.height /
                          _speed.boxDivider,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppTheme.primary.withOpacity(0.8),
                            width: 3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
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
                  // 2. kademe: foto cek + elle gir (gorme dostu)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _captureForManual,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.photo_camera_rounded, size: 18),
                      label: const Text('Fotoğraf Çek',
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
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(
                      color: AppTheme.statusSafe.withOpacity(0.4),
                      width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  child: Image.memory(
                    _capturedFrame!,
                    width: double.infinity,
                    fit: BoxFit.contain, // krop yok, tam goruntur
                  ),
                ),
              ),
              const SizedBox(height: 6),
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

              // Buyuk foto onizleme — kirpilmis tarih bolgesi
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
                    child: Image.memory(
                      widget.frame!,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
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
              const SizedBox(height: 20),

              const Text(
                'Fotoğraftaki tarihi gir',
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Gün · Ay · Yıl  (sadece rakam yaz)',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 18),

              // Buyuk tarih girisi — gorme dostu
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [_DateInputFormatter()],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
                onChanged: (_) => _parse(),
                decoration: InputDecoration(
                  hintText: 'GG.AA.YYYY',
                  hintStyle: TextStyle(
                    fontSize: 30,
                    color: AppTheme.textTertiary.withOpacity(0.5),
                    letterSpacing: 2,
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 2),
                  ),
                ),
              ),

              // Gecerli tarih onizleme
              const SizedBox(height: 14),
              AnimatedOpacity(
                opacity: _parsed != null ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.statusSafe, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _parsed != null
                          ? DateFormat('d MMMM yyyy', 'tr').format(_parsed!)
                          : '',
                      style: const TextStyle(
                        color: AppTheme.statusSafe,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Buyuk onay butonu
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _parsed != null ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.statusSafe,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Onayla',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Vazgeç',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 15)),
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
