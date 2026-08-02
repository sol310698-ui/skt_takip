import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/camera_lifecycle_mixin.dart';
import '../../core/services/scan_engine.dart';
import '../widgets/scan_mode_toggle.dart';

import '../../core/services/barcode_lookup_service.dart';
import '../../core/services/camera_helper.dart';
import '../../core/services/shelf_layout_service.dart';
import '../../core/utils/scan_parser.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/barcode_directory_datasource.dart';
import '../../core/services/database_service.dart';
import '../widgets/scan_overlay.dart';

/// ════════════════════════════════════════════════════════════════════
///  REYON TARAMA + FOTOGRAF
/// ────────────────────────────────────────────────────────────────────
///  Akis: kullanici hedef HUCREYI secer (bolum + satir), sonra urunleri
///  soldan saga sirayla okutur. Her okumada:
///    1) Barkod cozulur, urun adi (yerel dizin → internet) bulunur,
///    2) KAMERA acilir, urun fotografi cekilir,
///    3) Foto 720 px'e kucultulup KALICI kaydedilir,
///    4) Slot veritabanina eklenir; foto barkod dizinine de yerel foto olarak
///       yazilir (uygulama geneli fallback).
///  Ayni hucrede eklenenler altta kucuk kucuk gorunur (dizilim onizleme).
///  Bir satir bitince "Sonraki satır" ile ilerlenir.
/// ════════════════════════════════════════════════════════════════════
class ShelfScanScreen extends StatefulWidget {
  final ShelfUnit unit;
  final int startSection;
  final int startRow;
  const ShelfScanScreen({
    super.key,
    required this.unit,
    this.startSection = 1,
    this.startRow = 1,
  });

  @override
  State<ShelfScanScreen> createState() => _ShelfScanScreenState();
}

class _ShelfScanScreenState extends State<ShelfScanScreen> with CameraLifecycleMixin {
  // Kamera yasam dongusu: arka plandan donunce kamera unlem/takilma
  // yasamasin diye durdur/yeniden baslat.
  @override
  List<MobileScannerController> get cameraControllers => [_controller];
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: ScanEngine.broadFormats,
  );
  // Tarama modu: true = EAN-13 kesin (kontrol basamagi), false = hepsi.
  bool _strictScan = true;
  final BarcodeDirectoryDataSource _barcodeDs =
      BarcodeDirectoryDataSource(DatabaseService.instance);

  late int _section;
  late int _row;
  bool _busy = false;
  String? _lastMsg;
  bool _lastMsgError = false;

  List<ShelfSlot> _cellSlots = [];

  @override
  void initState() {
    super.initState();
    _section = widget.startSection;
    _row = widget.startRow;
    _loadCell();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadCell() async {
    final slots = await ShelfLayoutService.instance
        .getSlotsInCell(widget.unit.id!, _section, _row);
    if (mounted) setState(() => _cellSlots = slots);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final accepted = ScanEngine.accept(capture, strictEan13: _strictScan);
    if (accepted == null) return;
    final code = ScanParser.parse(accepted).barcode ?? accepted;
    _handle(code);
  }

  Future<void> _handle(String code) async {
    setState(() {
      _busy = true;
      _lastMsg = null;
    });
    HapticFeedback.mediumImpact();

    // Urun adi: once yerel dizin, sonra internet.
    String? name = await _barcodeDs.findProductName(code);
    name ??= await BarcodeLookupService.instance.lookupName(code);

    if (!mounted) return;

    // Fotograf cek (720 px, kalici, kucuk boyut).
    final photo = await CameraHelper.pickImageDownscaled(
      source: ImageSource.camera,
      maxSide: 720,
      quality: 80,
    );

    if (photo == null) {
      // Kullanici fotografi iptal etti — urunu fotosuz da eklemesin, akisi
      // bozmamak icin sadece uyar ve devam et.
      if (mounted) {
        setState(() {
          _busy = false;
          _lastMsg = 'Fotoğraf çekilmedi, ürün eklenmedi';
          _lastMsgError = true;
        });
      }
      return;
    }

    await ShelfLayoutService.instance.addSlot(
      unitId: widget.unit.id!,
      sectionNo: _section,
      rowNo: _row,
      barcode: code,
      productName: name,
      photoPath: photo,
    );

    await _loadCell();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastMsg = '${name ?? code} eklendi (Sütun $_section · Raf $_row)';
      _lastMsgError = false;
    });
  }

  Future<void> _pickCell() async {
    int s = _section;
    int r = _row;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Hücre seç'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _picker('Sütun', s, widget.unit.sections,
                  (v) => setD(() => s = v)),
              const SizedBox(height: 12),
              // Raf ust siniri SABIT DEGIL: sutun basina istenildigi kadar
              // raf. Pratik bir tavan (99) veriyoruz.
              _picker('Raf', r, 99, (v) => setD(() => r = v)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Seç')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _section = s;
        _row = r;
      });
      _loadCell();
    }
  }

  Widget _picker(String label, int value, int max, ValueChanged<int> onCh) {
    return Row(
      children: [
        SizedBox(
            width: 62,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton.filledTonal(
          onPressed: value > 1 ? () => onCh(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
            width: 40,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900))),
        IconButton.filledTonal(
          onPressed: value < max ? () => onCh(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
        Text('/ $max', style: TextStyle(color: AppTheme.textTertiary)),
      ],
    );
  }

  void _nextRow() {
    // Ayni sutunda BIR SONRAKI rafa gec (ust sinir yok). Boylece bir rafi
    // bitirince ayni sutunun yeni rafina serbestce devam edilir.
    setState(() {
      _row++;
    });
    _loadCell();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.unit.name} — okut'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── KAMERA ──
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                const ScanOverlay(
                  hint: 'Ürün barkodunu okutun → fotoğraf çekilecek',
                  accent: AppTheme.accent,
                ),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ScanModeToggle(
                      value: _strictScan,
                      onChanged: (v) => setState(() => _strictScan = v),
                    ),
                  ),
                ),
                if (_busy)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                // Hedef hucre rozeti.
                Positioned(
                  left: 12,
                  top: 12,
                  child: InkWell(
                    onTap: _pickCell,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.my_location_rounded,
                              size: 16, color: Colors.black),
                          const SizedBox(width: 6),
                          Text('Sütun $_section · Raf $_row',
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_rounded,
                              size: 14, color: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── ALT PANEL: bu hucredeki urunler + sonraki satir ──
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_lastMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _lastMsg!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _lastMsgError
                            ? AppTheme.statusExpired
                            : AppTheme.statusSafe,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Text('Bu hücre: ${_cellSlots.length} ürün',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _nextRow,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Sonraki raf'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: _cellSlots.isEmpty
                      ? Center(
                          child: Text('Henüz ürün yok — okutmaya başlayın',
                              style:
                                  TextStyle(color: AppTheme.textTertiary)),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _cellSlots.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final s = _cellSlots[i];
                            return _thumb(s);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(ShelfSlot s) {
    return GestureDetector(
      onLongPress: () async {
        await ShelfLayoutService.instance.deleteSlot(s.id!);
        _loadCell();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 72,
          height: 72,
          color: AppTheme.surfaceAlt,
          child: (s.photoPath != null && File(s.photoPath!).existsSync())
              ? Image.file(File(s.photoPath!), fit: BoxFit.cover)
              : Icon(Icons.inventory_2_rounded,
                  color: AppTheme.textTertiary),
        ),
      ),
    );
  }
}
