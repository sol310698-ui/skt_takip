import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/morning_label_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';

/// Sabah Etiket Kaydi Dogrulamasi.
/// Akis:
/// 1) "Gune Basla" -> personele verilen A4 listenin fotografi cekilir.
/// 2) Etiketler sirayla taranir; barkod + fiyat + tarihler kaydedilir.
/// 3) Kayitlar 30 gun saklanir.
/// 4) Sag alttaki "Sorgula" ile etiket okutulur: kayitliysa teslim gunu
///    gosterilir; fiyat farkliysa KIRMIZI "etiket degistirilmis" uyarisi.
class MorningVerifyScreen extends ConsumerStatefulWidget {
  const MorningVerifyScreen({super.key});

  @override
  ConsumerState<MorningVerifyScreen> createState() =>
      _MorningVerifyScreenState();
}

enum _Mode { idle, record, query }

class _MorningVerifyScreenState extends ConsumerState<MorningVerifyScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  _Mode _mode = _Mode.idle;
  String? _a4Photo;
  List<MorningLabel> _today = [];
  bool _processing = false;

  // Sorgu sonucu (query modunda gosterilir)
  MorningQueryResult? _queryResult;
  String? _queryBarcode; // sorgulanan ama bulunamayan barkod

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _loadToday();
    // 30 gunden eski kayitlari arka planda temizle.
    MorningLabelService.instance.purgeOld();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    // İzin verildi ve ekran zaten aktif moddaysa kamerayı başlat.
    if ((status.isGranted || status.isLimited) && _mode != _Mode.idle) {
      await _controller.start();
    }
    if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Kamera izni gerekli. Lutfen uygulama ayarlarindan izin verin.'),
          action: SnackBarAction(
            label: 'Ayarlar',
            onPressed: openAppSettings,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    final list = await MorningLabelService.instance.getToday();
    if (mounted) setState(() => _today = list);
  }

  /// Gune basla: once A4 liste fotografi.
  Future<void> _startDay() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo == null) {
      // Foto cekilmeden baslanamaz (istenen akis).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Güne başlamak için A4 listenin fotoğrafı gerekli')),
        );
      }
      return;
    }
    setState(() {
      _a4Photo = photo.path;
      _mode = _Mode.record;
    });
    await _controller.start();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _mode == _Mode.idle) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _processing = true);
    final parsed = ScanParser.parse(raw);
    final code = parsed.barcode;

    if (code == null) {
      setState(() => _processing = false);
      return;
    }

    if (_mode == _Mode.record) {
      await _recordLabel(parsed, code);
    } else {
      await _queryLabel(parsed, code);
    }
    if (mounted) setState(() => _processing = false);
  }

  /// KAYIT modu: etiketi DB'ye yaz.
  Future<void> _recordLabel(ScanResult parsed, String code) async {
    await MorningLabelService.instance.add(MorningLabel(
      barcode: code,
      price: parsed.price,
      labelExpiry: parsed.expiryDate,
      labelPrint: parsed.labelDateTime,
      scannedAt: DateTime.now(),
      a4Photo: _a4Photo,
    ));
    await _loadToday();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parsed.price != null
              ? 'Kaydedildi: $code — ${parsed.price!.toStringAsFixed(2)} ₺'
              : 'Kaydedildi: $code'),
          backgroundColor: AppTheme.statusSafe,
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  /// SORGU modu: etiketi son 30 gun icinde ara, fiyat farkini kontrol et.
  Future<void> _queryLabel(ScanResult parsed, String code) async {
    final record = await MorningLabelService.instance.findByBarcode(code);
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      if (record != null) {
        _queryResult = MorningQueryResult(
          record: record,
          currentPrice: parsed.price,
        );
        _queryBarcode = null;
      } else {
        _queryResult = null;
        _queryBarcode = code;
      }
    });
  }

  void _switchToQuery() async {
    setState(() {
      _mode = _Mode.query;
      _queryResult = null;
      _queryBarcode = null;
    });
    await _controller.start();
  }

  void _switchToRecord() async {
    setState(() {
      _mode = _Mode.record;
      _queryResult = null;
      _queryBarcode = null;
    });
    await _controller.start();
  }

  Future<void> _continueQuery() async {
    setState(() {
      _queryResult = null;
      _queryBarcode = null;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_mode == _Mode.query
            ? 'Etiket Sorgula'
            : 'Sabah Etiket Kaydı'),
        backgroundColor:
            _mode == _Mode.query ? AppTheme.accent : AppTheme.primary,
        foregroundColor:
            _mode == _Mode.query ? Colors.black : Colors.white,
      ),
      body: _mode == _Mode.idle ? _buildIdle() : _buildActive(),
      // Sag altta Sorgula / Kayda Don
      floatingActionButton: _mode == _Mode.idle
          ? null
          : FloatingActionButton.extended(
              onPressed:
                  _mode == _Mode.record ? _switchToQuery : _switchToRecord,
              backgroundColor: _mode == _Mode.record
                  ? AppTheme.accent
                  : AppTheme.primary,
              foregroundColor:
                  _mode == _Mode.record ? Colors.black : Colors.white,
              icon: Icon(_mode == _Mode.record
                  ? Icons.search_rounded
                  : Icons.qr_code_scanner),
              label:
                  Text(_mode == _Mode.record ? 'Sorgula' : 'Kayda Dön'),
            ),
    );
  }

  /// Baslangic: gune basla butonu.
  Widget _buildIdle() {
    return EmptyState(
      icon: Icons.wb_sunny_rounded,
      iconColor: AppTheme.amber,
      title: 'Güne Başla',
      subtitle:
          'Önce personele verilen A4 etiket listesinin fotoğrafı çekilir, '
          'sonra etiketler sırayla taranıp kaydedilir.\n'
          'Kayıtlar 30 gün saklanır.',
      action: Column(
        children: [
          FilledButton.icon(
            onPressed: _startDay,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('A4 Fotoğrafını Çek ve Başla'),
          ),
          const SizedBox(height: 10),
          // Sorgu, gune baslamadan da yapilabilsin (eski kayitlar icin).
          OutlinedButton.icon(
            onPressed: () async {
              setState(() => _mode = _Mode.query);
              await _controller.start();
            },
            icon: const Icon(Icons.search_rounded),
            label: const Text('Sadece Sorgula'),
          ),
        ],
      ),
    );
  }

  /// Aktif: ustte kamera, altta liste / sorgu sonucu.
  Widget _buildActive() {
    return Column(
      children: [
        // Kamera
        SizedBox(
          height: 260,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _controller, onDetect: _onDetect),
              Positioned(
                bottom: 10,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_mode == _Mode.query
                            ? AppTheme.accent
                            : AppTheme.primary)
                        .withOpacity(0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _mode == _Mode.record
                        ? 'Etiketleri sırayla okutun — otomatik kaydedilir'
                        : 'Sorgulanacak etiketi okutun',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _mode == _Mode.query
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Alt icerik
        Expanded(
          child: _mode == _Mode.query
              ? _buildQueryResult()
              : _buildTodayList(),
        ),
      ],
    );
  }

  /// Bugun kaydedilen etiketler.
  Widget _buildTodayList() {
    if (_today.isEmpty) {
      return const Center(
        child: Text('Henüz etiket kaydedilmedi',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }
    final fmtTime = DateFormat('HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            'Bugün kaydedilen: ${_today.length} etiket',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
            itemCount: _today.length,
            itemBuilder: (_, i) {
              final m = _today[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: AppTheme.card(),
                child: Row(
                  children: [
                    const Icon(Icons.label_rounded,
                        color: AppTheme.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(m.barcode,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13)),
                    ),
                    if (m.price != null)
                      Text('${m.price!.toStringAsFixed(2)} ₺',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.statusSafe)),
                    const SizedBox(width: 10),
                    Text(fmtTime.format(m.scannedAt),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textTertiary)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Sorgu sonucu paneli.
  Widget _buildQueryResult() {
    if (_queryResult == null && _queryBarcode == null) {
      return const Center(
        child: Text('Etiket okutun...',
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    // Kayit BULUNAMADI
    if (_queryBarcode != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: AppTheme.card(
                  accentColor: AppTheme.statusWarning),
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded,
                      color: AppTheme.statusWarning, size: 44),
                  const SizedBox(height: 10),
                  const Text('Kayıt Bulunamadı',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Bu barkod son 30 günün teslim kayıtlarında yok:\n$_queryBarcode',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _continueQuery,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Başka Etiket Sorgula'),
            ),
          ],
        ),
      );
    }

    // Kayit BULUNDU
    final r = _queryResult!;
    final fmt = DateFormat('dd MMMM yyyy', 'tr');
    final changed = r.priceChanged;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          // FIYAT DEGISMIS — KIRMIZI UYARI
          if (changed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.statusExpired.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.rLg),
                border:
                    Border.all(color: AppTheme.statusExpired, width: 1.5),
                boxShadow: AppTheme.glow(AppTheme.statusExpired),
              ),
              child: Column(
                children: [
                  const Icon(Icons.warning_rounded,
                      color: AppTheme.statusExpired, size: 44),
                  const SizedBox(height: 8),
                  const Text('ETİKET DEĞİŞTİRİLMİŞ!',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.statusExpired)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          const Text('Teslim günü fiyat',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary)),
                          Text(
                              '${r.record.price!.toStringAsFixed(2)} ₺',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Icon(Icons.arrow_forward_rounded,
                            color: AppTheme.statusExpired),
                      ),
                      Column(
                        children: [
                          const Text('Şimdiki etiket',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary)),
                          Text(
                              '${r.currentPrice!.toStringAsFixed(2)} ₺',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.statusExpired)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration:
                  AppTheme.card(accentColor: AppTheme.statusSafe),
              child: const Column(
                children: [
                  Icon(Icons.verified_rounded,
                      color: AppTheme.statusSafe, size: 44),
                  SizedBox(height: 8),
                  Text('Etiket Doğrulandı',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),

          // Kayit detaylari
          _qRow(Icons.qr_code_rounded, 'Barkod', r.record.barcode),
          _qRow(Icons.event_available_rounded, 'Teslim Alınan Gün',
              fmt.format(r.record.scannedAt)),
          if (r.record.price != null)
            _qRow(Icons.sell_rounded, 'Kayıtlı Fiyat',
                '${r.record.price!.toStringAsFixed(2)} ₺'),
          if (r.currentPrice != null)
            _qRow(Icons.sell_outlined, 'Okunan Fiyat',
                '${r.currentPrice!.toStringAsFixed(2)} ₺',
                color: changed ? AppTheme.statusExpired : null),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _continueQuery,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Başka Etiket Sorgula'),
          ),
        ],
      ),
    );
  }

  Widget _qRow(IconData icon, String label, String value, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.card(),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? AppTheme.primary),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color ?? AppTheme.textPrimary)),
        ],
      ),
    );
  }
}
