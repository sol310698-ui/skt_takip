import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/feedback_service.dart';
import '../../core/services/scan_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/count_item.dart';
import '../../viewmodels/providers.dart';
import '../widgets/resilient_scanner.dart';
import '../widgets/scan_mode_toggle.dart';
import '../widgets/scan_overlay.dart';
import '../widgets/ui_kit.dart';

/// ════════════════════════════════════════════════════════════════════
///  SAYIM — OTURUM TABANLI
/// ────────────────────────────────────────────────────────────────────
///  Her sayim ayri bir OTURUMDUR (ör. "Reyon 3 · 05.08"). Boylece farkli
///  sayimlar birbirine karismaz, gecmis oturumlar saklanir, biri kapatilip
///  yeni bir tanesi acilabilir.
///
///  Bu ekran OTURUM LISTESIDIR: oturum ac / sec / kapat / sil / rapor al.
///  Bir oturuma dokununca [_CountSessionScreen] acilir (asil sayim: barkod
///  okut → adet gir).
/// ════════════════════════════════════════════════════════════════════
class CountScreen extends ConsumerStatefulWidget {
  const CountScreen({super.key});

  @override
  ConsumerState<CountScreen> createState() => _CountScreenState();
}

class _CountScreenState extends ConsumerState<CountScreen> {
  List<CountSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(countRepositoryProvider).getSessions();
    if (mounted) {
      setState(() {
        _sessions = list;
        _loading = false;
      });
    }
  }

  Future<void> _newSession() async {
    final now = DateTime.now();
    final def = 'Sayım · ${DateFormat('dd.MM HH:mm').format(now)}';
    final name = await _promptName('Yeni Sayım', def);
    if (name == null) return;
    final id = await ref.read(countRepositoryProvider).createSession(name);
    if (!mounted) return;
    await _openSession(CountSession(id: id, name: name, createdAt: now));
    _load();
  }

  Future<String?> _promptName(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: initial.length);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Oturum adı',
            hintText: 'ör. Reyon 3 sayımı',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Tamam')),
        ],
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  }

  Future<void> _openSession(CountSession s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CountSessionScreen(session: s),
    ));
    _load(); // donunce ozetleri tazele
  }

  Future<void> _rename(CountSession s) async {
    final name = await _promptName('Yeniden Adlandır', s.name);
    if (name == null || s.id == null) return;
    await ref.read(countRepositoryProvider).renameSession(s.id!, name);
    _load();
  }

  Future<void> _toggleClosed(CountSession s) async {
    if (s.id == null) return;
    await ref.read(countRepositoryProvider).setClosed(s.id!, !s.isClosed);
    _load();
  }

  Future<void> _delete(CountSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('“${s.name}” silinsin mi?'),
        content: Text(
            'Bu oturum ve içindeki ${s.itemCount} kalem kalıcı olarak silinecek.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusExpired),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true && s.id != null) {
      await ref.read(countRepositoryProvider).deleteSession(s.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sayım')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSession,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni Sayım'),
      ),
      body: _loading
          ? const LoadingState(message: 'Yükleniyor')
          : _sessions.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Henüz sayım oturumu yok',
                  subtitle:
                      'Sağ alttaki “Yeni Sayım” ile bir oturum başlat; barkod '
                      'okutup adet gir. Her sayım ayrı tutulur.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: _sessions.length,
                    itemBuilder: (_, i) => _sessionCard(_sessions[i]),
                  ),
                ),
    );
  }

  Widget _sessionCard(CountSession s) {
    final closed = s.isClosed;
    final accent = closed ? AppTheme.textTertiary : AppTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppTheme.card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          onTap: () => _openSession(s),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                      closed
                          ? Icons.lock_outline_rounded
                          : Icons.play_circle_fill_rounded,
                      color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                          _statusChip(closed),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd.MM.yyyy · HH:mm').format(s.createdAt),
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _miniStat('${s.itemCount}', 'kalem'),
                          const SizedBox(width: 16),
                          _miniStat('${s.totalQty}', 'adet'),
                        ],
                      ),
                    ],
                  ),
                ),
                _menu(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(bool closed) {
    final c = closed ? AppTheme.textTertiary : AppTheme.statusSafe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(closed ? 'Kapalı' : 'Açık',
          style:
              TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  Widget _miniStat(String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppTheme.primary)),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _menu(CountSession s) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: AppTheme.textTertiary),
      onSelected: (v) {
        switch (v) {
          case 'rename':
            _rename(s);
            break;
          case 'toggle':
            _toggleClosed(s);
            break;
          case 'delete':
            _delete(s);
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
        PopupMenuItem(
            value: 'toggle',
            child: Text(s.isClosed ? 'Yeniden aç' : 'Oturumu kapat')),
        const PopupMenuItem(value: 'delete', child: Text('Sil')),
      ],
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  TEK OTURUM — asil sayim ekrani (barkod okut → adet gir).
/// ════════════════════════════════════════════════════════════════════
class _CountSessionScreen extends ConsumerStatefulWidget {
  final CountSession session;
  const _CountSessionScreen({required this.session});

  @override
  ConsumerState<_CountSessionScreen> createState() =>
      _CountSessionScreenState();
}

class _CountSessionScreenState extends ConsumerState<_CountSessionScreen> {
  MobileScannerController? _controller;
  MobileScannerController _createController() => MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        formats: ScanEngine.broadFormats,
      );

  bool _strictScan = true;
  final TextEditingController _qtyController = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();

  int get _sid => widget.session.id!;
  late bool _closed = widget.session.isClosed;
  late String _name = widget.session.name;

  List<CountItem> _items = [];
  bool _loading = true;

  String? _activeBarcode;
  String? _activeName;
  CountItem? _activeExisting;
  bool _scanPaused = false;

  String? _lastMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ref.read(countRepositoryProvider).getItems(_sid);
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

    final existing =
        await ref.read(countRepositoryProvider).findByBarcode(_sid, code);
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
        sessionId: _sid,
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
          FilledButton(
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

  Future<void> _toggleClosed() async {
    await ref.read(countRepositoryProvider).setClosed(_sid, !_closed);
    if (mounted) setState(() => _closed = !_closed);
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
                pw.Text('Sayım Raporu — $_name',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
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
    await Share.shareXFiles([XFile(file.path)], text: 'Sayım raporu · $_name');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_closed)
            IconButton(
              tooltip: 'El feneri',
              icon: const Icon(Icons.flash_on_rounded),
              onPressed: () => _controller?.toggleTorch(),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'pdf') _pdfReport();
              if (v == 'xlsx') _excelReport();
              if (v == 'toggle') _toggleClosed();
            },
            itemBuilder: (_) => [
              if (_items.isNotEmpty) ...[
                const PopupMenuItem(value: 'pdf', child: Text('PDF rapor')),
                const PopupMenuItem(value: 'xlsx', child: Text('Excel rapor')),
              ],
              PopupMenuItem(
                  value: 'toggle',
                  child: Text(_closed ? 'Yeniden aç' : 'Oturumu kapat')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const LoadingState(message: 'Yükleniyor')
          : Column(
              children: [
                _statsBar(),
                if (!_closed) ...[
                  SizedBox(height: 230, child: _scannerArea()),
                  if (_activeBarcode != null)
                    _qtyEntry()
                  else
                    _lastMsgBar(),
                ] else
                  _closedBanner(),
                const Divider(height: 1),
                Expanded(child: _list()),
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
        Text(label,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _scannerArea() {
    return Stack(
      alignment: Alignment.center,
      children: [
        ResilientScanner(
          create: _createController,
          onDetect: _onDetect,
          onReady: (c) => _controller = c,
          accent: AppTheme.primary,
        ),
        ScanOverlay(
          hint: _activeBarcode != null ? 'Adet girin' : 'Ürün barkodunu okutun',
          accent: _activeBarcode != null ? AppTheme.amber : AppTheme.primary,
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

  Widget _closedBanner() {
    return Container(
      width: double.infinity,
      color: AppTheme.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Bu oturum kapalı — salt görüntüleme.',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton.icon(
            onPressed: _toggleClosed,
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Yeniden aç'),
          ),
        ],
      ),
    );
  }

  Widget _qtyEntry() {
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
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          Text('Barkod: $_activeBarcode',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          if (_activeExisting != null)
            Text('Önceki: ${_activeExisting!.qty} adet (üzerine yazılacak)',
                style:
                    TextStyle(fontSize: 11, color: AppTheme.statusWarning)),
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
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
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

  Widget _lastMsgBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _lastMsg == null
          ? AppTheme.surface
          : AppTheme.statusSuccess.withOpacity(0.12),
      child: _lastMsg == null
          ? Text('Barkod okutun',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary))
          : Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppTheme.statusSuccess, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('$_lastMsg kaydedildi',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary))),
              ],
            ),
    );
  }

  Widget _list() {
    if (_items.isEmpty) {
      return Center(
        child: Text('Henüz sayım yok',
            style: TextStyle(color: AppTheme.textTertiary)),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _items[i];
        return Dismissible(
          key: ValueKey(e.id),
          direction: _closed
              ? DismissDirection.none
              : DismissDirection.endToStart,
          background: Container(
            color: AppTheme.statusExpired,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _deleteItem(e),
          child: ListTile(
            dense: true,
            onTap: _closed ? null : () => _editItem(e),
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
