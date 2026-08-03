import 'dart:async';
import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/services/feedback_service.dart';
import '../widgets/scan_error_retry.dart';
import '../../core/camera_lifecycle_mixin.dart';
import '../../core/services/scan_engine.dart';
import '../widgets/scan_mode_toggle.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/count_item.dart';
import '../../viewmodels/providers.dart';
import '../widgets/scan_overlay.dart';

/// ════════════════════════════════════════════════════════════════════
///  SAYIM (BAGIMSIZ)
/// ────────────────────────────────────────────────────────────────────
///  Basit sayim: barkod okut -> adet gir -> kaydet. Urun adi (varsa)
///  barkod dizininden bulunur. Okunan tum kayitlar altta listelenir;
///  duzeltilip silinebilir. PDF/Excel rapor alinabilir.
/// ════════════════════════════════════════════════════════════════════
class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({super.key});

  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> with CameraLifecycleMixin {
  // Kamera yasam dongusu: arka plandan donunce kamera unlem/takilma
  // yasamasin diye durdur/yeniden baslat.
  @override
  List<MobileScannerController> get cameraControllers => [_controller];
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: ScanEngine.broadFormats,
  );
  // Tarama modu: true = EAN-13 kesin (kontrol basamagi), false = hepsi (Code128).
  bool _strictScan = true;
  final TextEditingController _qtyController = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();

  List<CountItem> _items = [];
  bool _loading = true;

  // O an okutulan barkod (adet bekleniyor).
  String? _activeBarcode;
  String? _activeName;
  CountItem? _activeExisting; // bu barkod daha once sayildiysa
  bool _scanPaused = false;

  String? _lastMsg;
  bool _lastMsgError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _qtyController.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ref.read(countRepositoryProvider).getAll();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  int get _totalQty => _items.fold(0, (s, e) => s + e.qty);

  void _onDetect(BarcodeCapture capture) {
    if (_scanPaused || _activeBarcode != null) return;
    final code = ScanEngine.accept(capture, strictEan13: _strictScan);
    if (code == null) return;
    _handleBarcode(code);
  }

  Future<void> _handleBarcode(String code) async {
    HapticFeedback.mediumImpact();
    FeedbackService.instance.play(ScanFeedback.product);
    setState(() => _scanPaused = true);

    // Bu barkod daha once sayildi mi?
    final existing = await ref.read(countRepositoryProvider).findByBarcode(code);
    // Urun adini dizinden bul.
    final name = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .findProductName(code);

    if (!mounted) return;
    setState(() {
      _activeBarcode = code;
      _activeName = name ?? existing?.productName;
      _activeExisting = existing;
      _qtyController.text = existing?.qty.toString() ?? '';
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _qtyFocus.requestFocus();
      _qtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyController.text.length,
      );
    });
  }

  Future<void> _save() async {
    final code = _activeBarcode;
    if (code == null) return;
    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty < 0) {
      HapticFeedback.heavyImpact();
      return;
    }
    final repo = ref.read(countRepositoryProvider);
    final existing = _activeExisting;
    if (existing != null && existing.id != null) {
      await repo.updateQty(existing.id!, qty);
    } else {
      await repo.insert(CountItem(
        barcode: code,
        productName: _activeName,
        qty: qty,
        countedAt: DateTime.now(),
      ));
    }

    HapticFeedback.lightImpact();
    final savedName = _activeName ?? code;
    setState(() {
      _activeBarcode = null;
      _activeName = null;
      _activeExisting = null;
      _scanPaused = false;
      _qtyController.clear();
      _lastMsg = '$savedName → $qty adet';
      _lastMsgError = false;
    });
    await _load();
  }

  void _cancel() {
    setState(() {
      _activeBarcode = null;
      _activeName = null;
      _activeExisting = null;
      _scanPaused = false;
      _qtyController.clear();
    });
  }

  Future<void> _editItem(CountItem item) async {
    final controller = TextEditingController(text: item.qty.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.productName ?? item.barcode),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Adet'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text.trim())),
              child: const Text('Kaydet')),
        ],
      ),
    );
    if (result != null && result >= 0 && item.id != null) {
      await ref.read(countRepositoryProvider).updateQty(item.id!, result);
      await _load();
    }
  }

  Future<void> _deleteItem(CountItem item) async {
    if (item.id == null) return;
    await ref.read(countRepositoryProvider).deleteById(item.id!);
    await _load();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sayımı sıfırla'),
        content: const Text('Tüm sayım kayıtları silinecek. Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(countRepositoryProvider).clearAll();
      await _load();
    }
  }

  // ── PDF RAPOR ──
  Future<void> _pdfReport() async {
    if (_items.isEmpty) return;
    final now = DateTime.now();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Sayım Raporu',
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(
                    'Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(now)}',
                    style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStat('Kalem', '${_items.length}', PdfColors.blue800),
              _pdfStat('Toplam Adet', '$_totalQty', PdfColors.green800),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Ürün Adı', 'Barkod', 'Adet'],
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {
              0: pw.Alignment.center,
              3: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FlexColumnWidth(3.5),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FixedColumnWidth(60),
            },
            data: List.generate(_items.length, (i) {
              final e = _items[i];
              return [
                '${i + 1}',
                e.productName ?? '(isimsiz)',
                e.barcode,
                '${e.qty}',
              ];
            }),
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'sayim_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf',
    );
  }

  pw.Widget _pdfStat(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: color, width: 1.5),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: color)),
            pw.SizedBox(height: 2),
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── EXCEL RAPOR ──
  Future<void> _excelReport() async {
    if (_items.isEmpty) return;
    final now = DateTime.now();
    final excel = Excel.createExcel();
    final sheet = excel['Sayım'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('#'),
      TextCellValue('Ürün Adı'),
      TextCellValue('Barkod'),
      TextCellValue('Adet'),
      TextCellValue('Zaman'),
    ]);
    for (var i = 0; i < _items.length; i++) {
      final e = _items[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(e.productName ?? ''),
        TextCellValue(e.barcode),
        IntCellValue(e.qty),
        TextCellValue(DateFormat('dd.MM.yyyy HH:mm').format(e.countedAt)),
      ]);
    }
    sheet.appendRow([
      TextCellValue(''),
      TextCellValue('TOPLAM'),
      TextCellValue(''),
      IntCellValue(_totalQty),
      TextCellValue(''),
    ]);
    final bytes = excel.encode();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/sayim_${DateFormat('yyyyMMdd_HHmm').format(now)}.xlsx');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Sayım raporu');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sayım'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'El feneri',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
          if (_items.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Rapor',
              icon: const Icon(Icons.summarize_rounded),
              onSelected: (v) {
                if (v == 'pdf') _pdfReport();
                if (v == 'xlsx') _excelReport();
                if (v == 'clear') _clearAll();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('PDF rapor')),
                PopupMenuItem(value: 'xlsx', child: Text('Excel rapor')),
                PopupMenuItem(value: 'clear', child: Text('Sayımı sıfırla')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _statsBar(),
                SizedBox(height: 230, child: _scannerArea()),
                if (_activeBarcode != null)
                  _qtyEntry(cs)
                else
                  _lastMsgBar(cs),
                const Divider(height: 1),
                Expanded(child: _list(cs)),
              ],
            ),
    );
  }

  Widget _statsBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.primary.withOpacity(0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('Kalem', '${_items.length}'),
          _stat('Toplam Adet', '$_totalQty'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _scannerArea() {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect, errorBuilder: (context, error, child) => ScanErrorRetry(controller: _controller)),
        ScanOverlay(
          hint: _activeBarcode != null
              ? 'Adet girin'
              : 'Ürün barkodunu okutun',
          accent: _activeBarcode != null ? Colors.orange : AppTheme.primary,
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
      ],
    );
  }

  Widget _qtyEntry(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      color: AppTheme.primary.withOpacity(0.06),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_activeName ?? '(dizinde yok)',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text('Barkod: $_activeBarcode',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
          if (_activeExisting != null)
            Text('Önceki: ${_activeExisting!.qty} adet (üzerine yazılacak)',
                style: TextStyle(fontSize: 11, color: AppTheme.statusWarning)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  focusNode: _qtyFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Adet',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.statusSuccess,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Kaydet',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                onPressed: _cancel,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lastMsgBar(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _lastMsg == null
          ? cs.surface
          : AppTheme.statusSuccess.withOpacity(0.12),
      child: _lastMsg == null
          ? Text('Barkod okutun',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withOpacity(0.6)))
          : Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppTheme.statusSuccess, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('$_lastMsg kaydedildi',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
    );
  }

  Widget _list(ColorScheme cs) {
    if (_items.isEmpty) {
      return Center(
        child: Text('Henüz sayım yok',
            style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _items[i];
        return Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _deleteItem(e),
          child: ListTile(
            dense: true,
            onTap: () => _editItem(e),
            title: Text(e.productName ?? '(isimsiz)',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(e.barcode, style: const TextStyle(fontSize: 12)),
            trailing: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${e.qty}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary)),
            ),
          ),
        );
      },
    );
  }
}
