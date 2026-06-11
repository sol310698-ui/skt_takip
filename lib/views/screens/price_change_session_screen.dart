import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/price_change_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';
import 'image_zoom_screen.dart';
import 'price_change_review_screen.dart';
import 'web_search_screen.dart';

/// Tek fiyat degisim oturumunun detayi.
/// Aktif: kamera ile uygula (foto kanitli). Tamamlanmis: rapor + kanitlar.
class PriceChangeSessionScreen extends StatefulWidget {
  final int sessionId;
  const PriceChangeSessionScreen({super.key, required this.sessionId});

  @override
  State<PriceChangeSessionScreen> createState() =>
      _PriceChangeSessionScreenState();
}

class _PriceChangeSessionScreenState
    extends State<PriceChangeSessionScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  PriceChangeSession? _session;
  List<PriceChangeItem> _items = [];
  bool _busy = false;
  PriceChangeItem? _matched;
  String? _scanMessage;

  bool get _completed => _session?.isCompleted ?? false;

  @override
  void initState() {
    super.initState();
    _load(startCamera: true);
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _load({bool startCamera = false}) async {
    final s =
        await PriceChangeService.instance.getSession(widget.sessionId);
    final items =
        await PriceChangeService.instance.getItems(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = s;
      _items = items;
    });
    if (startCamera && !(s?.isCompleted ?? true)) {
      await _scanner.start();
    }
  }

  // ─────────────────────────── A4 ekleme (Gemini -> ML Kit) ──────────
  Future<void> _captureA4() async {
    final photo = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 92);
    if (photo == null) return;

    setState(() => _busy = true);
    await _scanner.stop();

    List<PriceChangeItem> parsed = [];
    String source = 'Gemini AI';

    // 1) Gemini (online, dogruluk yuksek)
    try {
      parsed = await GeminiOcrService.instance
          .extractTable(File(photo.path), widget.sessionId);
    } catch (e) {
      // 2) Fallback: ML Kit yerel
      source = 'Cihaz OCR';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Online okuma yapılamadı ($e) — cihaz OCR kullanılıyor')),
        );
      }
      final recognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final input = InputImage.fromFilePath(photo.path);
        final result = await recognizer.processImage(input);
        parsed = PriceChangeParser.parse(result.text, widget.sessionId);
      } catch (_) {
      } finally {
        recognizer.close();
      }
    }

    if (!mounted) return;

    if (parsed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Sayfadan satır okunamadı. Daha net çekmeyi deneyin.')),
      );
      return;
    }

    // 3) ONIZLEME — kullanici duzeltir/onaylar (hata kabul yok).
    final confirmed =
        await Navigator.of(context).push<List<PriceChangeItem>>(
      MaterialPageRoute(
        builder: (_) =>
            PriceChangeReviewScreen(items: parsed, source: source),
      ),
    );

    if (confirmed == null || confirmed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      return;
    }

    final added = await PriceChangeService.instance.addA4ToSession(
      sessionId: widget.sessionId,
      tempPhotoPath: photo.path,
      items: confirmed,
    );
    // Barkod dizinini zenginlestir (yeni barkod+ad ciftleri).
    final enriched =
        await PriceChangeService.instance.enrichDirectory(confirmed);
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added ürün eklendi (toplam ${_items.length})'
              '${enriched > 0 ? " • $enriched yeni ürün dizine kaydedildi" : ""}'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  // ─────────────────────────── Excel ice aktarma ─────────────────────
  /// Baska uygulamadan taranmis Excel'i (Barkod|Ad|StokKodu|Fiyat|Eski|Reyon)
  /// oturuma yukler. OCR'siz, %100 dogru veri kaynagi.
  Future<void> _importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya okunamadı')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    await _scanner.stop();

    final parsed = <PriceChangeItem>[];
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.sheets.keys.first;
      final sheet = excel.sheets[sheetName]!;
      final now = DateTime.now();
      final seen = <String>{};

      double? toPrice(String? s) {
        if (s == null || s.trim().isEmpty) return null;
        return double.tryParse(s.trim().replaceAll(',', '.'));
      }

      for (int i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        String cell(int c) =>
            c < row.length ? (row[c]?.value?.toString().trim() ?? '') : '';

        final barcode = cell(0);

        // Baslik satirini atla.
        if (i == 0) {
          final lower = barcode.toLowerCase();
          if (lower.contains('barkod') ||
              lower.contains('barcode') ||
              !RegExp(r'\d').hasMatch(barcode)) {
            continue;
          }
        }

        // Gecerli barkod: 12-13 hane sayi.
        if (!RegExp(r'^\d{12,13}$').hasMatch(barcode)) continue;
        if (seen.contains(barcode)) continue;
        seen.add(barcode);

        final name = cell(1).replaceAll('*', '').trim();
        // cell(2) = Stok Kodu — kullanilmiyor.
        final newPrice = toPrice(cell(3));
        final oldPrice = toPrice(cell(4));
        final aisle = cell(5);

        parsed.add(PriceChangeItem(
          batchId: 'excel',
          sessionId: widget.sessionId,
          barcode: barcode,
          productName: name.isEmpty ? null : name,
          newPrice: newPrice,
          oldPrice: oldPrice,
          aisle: aisle.isEmpty ? null : aisle,
          createdAt: now,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _scanner.start();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel okunamadı: $e')),
        );
      }
      return;
    }

    if (!mounted) return;

    if (parsed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Excel\'de geçerli satır bulunamadı. Format: '
                'Barkod | Stok Adı | Stok Kodu | Fiyatı | Eski Fiyatı | Reyonu')),
      );
      return;
    }

    // Onizleme — Excel verisi de kontrol edilir (tutarlilik).
    final confirmed =
        await Navigator.of(context).push<List<PriceChangeItem>>(
      MaterialPageRoute(
        builder: (_) =>
            PriceChangeReviewScreen(items: parsed, source: 'Excel'),
      ),
    );

    if (confirmed == null || confirmed.isEmpty) {
      setState(() => _busy = false);
      await _scanner.start();
      return;
    }

    final added = await PriceChangeService.instance
        .addItemsToSession(widget.sessionId, confirmed);
    // Barkod dizinini zenginlestir: yeni barkod+ad ciftlerini kaydet.
    final enriched =
        await PriceChangeService.instance.enrichDirectory(confirmed);
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added ürün eklendi (toplam ${_items.length})'
              '${enriched > 0 ? " • $enriched yeni ürün dizine kaydedildi" : ""}'),
          backgroundColor: AppTheme.statusSafe,
        ),
      );
    }
  }

  // ─────────────────────────── Reyon uygulama ────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _matched != null || _completed) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    final code = ScanParser.parse(raw).barcode;
    if (code == null) return;

    final item = await PriceChangeService.instance
        .findInSession(widget.sessionId, code);
    if (!mounted) return;
    if (item == null) {
      setState(() => _scanMessage = 'Listede yok: $code');
      return;
    }
    if (item.changed) {
      setState(() => _scanMessage =
          '${item.productName ?? code} zaten değiştirildi ✓');
      return;
    }
    await _scanner.stop();
    setState(() {
      _matched = item;
      _scanMessage = null;
    });
  }

  Future<void> _confirmChange() async {
    final item = _matched;
    if (item == null || item.id == null) return;
    final photo = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo == null) return; // foto ZORUNLU

    setState(() => _busy = true);
    await PriceChangeService.instance.markChanged(item.id!, photo.path);
    await _load();
    if (!mounted) return;
    setState(() {
      _matched = null;
      _busy = false;
    });

    final pending = _items.where((i) => !i.changed).length;
    if (pending == 0 && _items.isNotEmpty) {
      // KUSURSUZ AKIS: hepsi bitti -> tamamlama onerisi.
      _offerComplete();
    } else {
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('✓ ${item.productName ?? item.barcode} — Kalan: $pending'),
          backgroundColor: AppTheme.statusSafe,
          duration: const Duration(milliseconds: 1100),
        ),
      );
    }
  }

  Future<void> _cancelMatch() async {
    setState(() => _matched = null);
    await _scanner.start();
  }

  // ─────────────────────────── Tamamlama ─────────────────────────────
  Future<void> _offerComplete() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration_rounded,
                color: AppTheme.statusSafe, size: 26),
            SizedBox(width: 10),
            Text('Hepsi Tamam!'),
          ],
        ),
        content: const Text(
            'Listedeki tüm etiketler değiştirildi. Oturumu bitirelim mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Henüz değil')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oturumu Bitir')),
        ],
      ),
    );
    if (ok == true) {
      await _finishSession();
    } else {
      await _scanner.start();
    }
  }

  Future<void> _finishSession({bool force = false}) async {
    final pending = _items.where((i) => !i.changed).length;
    if (pending > 0 && !force) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eksik Var'),
          content: Text(
              '$pending etiket henüz değiştirilmedi. Yine de bitirilsin mi? '
              '(Eksikler raporda görünür)'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Devam Et')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.statusWarning),
              child: const Text('Yine de Bitir'),
            ),
          ],
        ),
      );
      if (ok != true) {
        await _scanner.start();
        return;
      }
    }
    await _scanner.stop();
    await PriceChangeService.instance.completeSession(widget.sessionId);
    await _load();
  }

  // ─────────────────────────── Rapor paylas ──────────────────────────
  Future<void> _shareReport() async {
    final pending = _items.where((i) => !i.changed).toList();
    final done = _items.where((i) => i.changed).toList();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    final buf = StringBuffer();
    buf.writeln('FİYAT DEĞİŞİM RAPORU');
    if (_session != null) {
      buf.writeln('Oturum: ${fmt.format(_session!.createdAt)}'
          '${_session!.completedAt != null ? " → ${fmt.format(_session!.completedAt!)}" : ""}');
      buf.writeln('A4 sayfa: ${_session!.a4Count}');
    }
    buf.writeln('Toplam: ${_items.length} | '
        'Değiştirildi: ${done.length} | Kalan: ${pending.length}');
    buf.writeln('');
    if (pending.isNotEmpty) {
      buf.writeln('═══ DEĞİŞTİRİLMEYEN ETİKETLER ═══');
      for (final i in pending) {
        final price =
            i.newPrice != null ? '${i.newPrice!.toStringAsFixed(2)} ₺' : '-';
        buf.writeln('• ${i.barcode}  ${i.productName ?? ""}  → $price'
            '${i.aisle != null ? "  [${i.aisle}]" : ""}');
      }
    } else {
      buf.writeln('✓ Tüm etiketler değiştirildi.');
    }
    await Share.share(buf.toString(), subject: 'Fiyat Değişim Raporu');
  }

  // ─────────────────────────── Kanit galerisi ────────────────────────
  void _openEvidence() {
    final proofs = _items
        .where((i) => i.photoPath != null)
        .map((i) => (i.photoPath!, i.productName ?? i.barcode))
        .toList();
    final a4s = _session?.a4Photos ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Kanıtlar',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              if (a4s.isNotEmpty) ...[
                const SectionLabel('A4 Listeler'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: a4s.length,
                    itemBuilder: (_, i) => _thumb(
                        a4s[i], 'A4 Sayfa ${i + 1}',
                        width: 86, height: 110),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              SectionLabel('Etiket Kanıtları (${proofs.length})'),
              const SizedBox(height: 8),
              if (proofs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('Henüz kanıt fotoğrafı yok',
                        style:
                            TextStyle(color: AppTheme.textSecondary)),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: proofs.length,
                  itemBuilder: (_, i) =>
                      _thumb(proofs[i].$1, proofs[i].$2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(String path, String title,
      {double? width, double? height}) {
    final exists = File(path).existsSync();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: exists
            ? () =>
                openImageZoom(context, filePath: path, title: title)
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          child: exists
              ? Image.file(File(path),
                  width: width, height: height, fit: BoxFit.cover)
              : Container(
                  width: width ?? 86,
                  height: height ?? 86,
                  color: AppTheme.surfaceAlt,
                  child: const Icon(Icons.broken_image_rounded,
                      color: AppTheme.textTertiary),
                ),
        ),
      ),
    );
  }

  // ─────────────────────────── UI ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM', 'tr');
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_session != null
            ? 'Oturum — ${fmt.format(_session!.createdAt)}'
            : 'Oturum'),
        backgroundColor:
            _completed ? AppTheme.statusSafe : AppTheme.primary,
        foregroundColor: _completed ? Colors.black : Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_rounded),
            tooltip: 'Kanıtlar',
            onPressed: _openEvidence,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Raporu Paylaş',
            onPressed: _items.isEmpty ? null : _shareReport,
          ),
          if (!_completed)
            IconButton(
              icon: const Icon(Icons.flag_rounded),
              tooltip: 'Oturumu Bitir',
              onPressed: _items.isEmpty ? null : () => _finishSession(),
            ),
        ],
      ),
      body: _session == null
          ? const LoadingState()
          : (_completed ? _buildCompletedView() : _buildActiveView()),
    );
  }

  Widget _buildActiveView() {
    final pending = _items.where((i) => !i.changed).length;
    final total = _items.length;

    if (total == 0) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        iconColor: AppTheme.amber,
        title: 'Liste Ekleyin',
        subtitle:
            'İmzalı A4 sayfasını tarayın (fotoğraf + AI okuma) ya da '
            'başka uygulamadan aldığınız Excel dosyasını içe aktarın. '
            'Birden fazla kaynak ekleyebilirsiniz.',
        action: Column(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _captureA4,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.document_scanner_rounded),
              label: Text(_busy ? 'Okunuyor...' : 'A4 Tara'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importExcel,
              icon: const Icon(Icons.table_chart_rounded),
              label: const Text('Excel İçe Aktar'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 230,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _scanner, onDetect: _onDetect),
              if (_scanMessage != null)
                Positioned(
                  bottom: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.statusWarning.withOpacity(0.94),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_scanMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ),
              if (_busy)
                Container(
                  color: Colors.black54,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white)),
                ),
            ],
          ),
        ),
        if (_matched != null) _buildMatchedPanel(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kalan: $pending / $total',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0
                            ? 0
                            : (total - pending) / total,
                        minHeight: 5,
                        backgroundColor: AppTheme.surfaceAlt,
                        color: AppTheme.statusSafe,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (v) {
                  if (v == 'a4') _captureA4();
                  if (v == 'excel') _importExcel();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'a4',
                    child: Row(
                      children: [
                        Icon(Icons.document_scanner_rounded,
                            size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('A4 Tara'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_rounded,
                            size: 18, color: AppTheme.accent),
                        SizedBox(width: 8),
                        Text('Excel İçe Aktar'),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add_rounded,
                          size: 18, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text('Ekle',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildItemList()),
      ],
    );
  }

  Widget _buildMatchedPanel() {
    final item = _matched!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(accentColor: AppTheme.statusSafe),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.productName ?? item.barcode,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (item.oldPrice != null) ...[
                Text('${item.oldPrice!.toStringAsFixed(2)} ₺',
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: AppTheme.textTertiary)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 16, color: AppTheme.textSecondary),
                ),
              ],
              Text(
                item.newPrice != null
                    ? '${item.newPrice!.toStringAsFixed(2)} ₺'
                    : 'Fiyat yok',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.statusSafe),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancelMatch,
                  child: const Text('İptal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirmChange,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Foto Çek & Onayla',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.statusSafe),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    if (_items.isEmpty) {
      return const Center(child: Text('Liste boş'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          onTap: () {
            // Degistirilmis -> kanit fotografi; degilse -> internette ara.
            if (item.changed && item.photoPath != null) {
              openImageZoom(context,
                  filePath: item.photoPath!,
                  title: item.productName ?? item.barcode);
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WebSearchScreen(query: item.barcode),
              ));
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: AppTheme.card(
                accentColor: item.changed ? AppTheme.statusSafe : null),
            child: Row(
              children: [
                Icon(
                  item.changed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: item.changed
                      ? AppTheme.statusSafe
                      : AppTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName ?? item.barcode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: item.changed
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary)),
                      Text(
                          '${item.barcode}'
                          '${item.aisle != null ? "  •  ${item.aisle}" : ""}',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
                // Kanit fotografi gostergesi
                if (item.changed && item.photoPath != null)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.photo_camera_rounded,
                        size: 16, color: AppTheme.accent),
                  ),
                if (item.newPrice != null)
                  Text('${item.newPrice!.toStringAsFixed(2)} ₺',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: item.changed
                              ? AppTheme.textTertiary
                              : AppTheme.statusSafe)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompletedView() {
    final pending = _items.where((i) => !i.changed).toList();
    final done = _items.where((i) => i.changed).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                    label: 'Toplam',
                    count: _items.length,
                    color: AppTheme.primary,
                    icon: Icons.list_alt_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                    label: 'Değişti',
                    count: done,
                    color: AppTheme.statusSafe,
                    icon: Icons.check_circle_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                    label: 'Eksik',
                    count: pending.length,
                    color: pending.isEmpty
                        ? AppTheme.statusSafe
                        : AppTheme.statusExpired,
                    icon: pending.isEmpty
                        ? Icons.task_alt_rounded
                        : Icons.error_rounded),
              ),
            ],
          ),
        ),
        if (pending.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Değiştirilmeyenler:',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        const SizedBox(height: 6),
        Expanded(child: _buildItemList()),
      ],
    );
  }
}
