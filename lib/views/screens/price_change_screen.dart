import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/price_change_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/scan_parser.dart';
import '../widgets/ui_kit.dart';
import 'web_search_screen.dart';

/// Fiyat Degisim Is Akisi:
/// 1) Imzali A4 fiyat degisim sayfasi foto -> OCR -> kalemler cikarilir.
/// 2) Reyonda etiket okutulur -> listede varsa yeni fiyati gosterir ->
///    yeni etiket takilir -> FOTO cekilir (zorunlu) -> "degistirildi".
/// 3) Gun sonu: okutulmayan (degistirilmemis) kalemler raporlanir + paylasilir.
class PriceChangeScreen extends StatefulWidget {
  const PriceChangeScreen({super.key});

  @override
  State<PriceChangeScreen> createState() => _PriceChangeScreenState();
}

enum _Stage { loading, empty, apply, report }

class _PriceChangeScreenState extends State<PriceChangeScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  _Stage _stage = _Stage.loading;
  List<PriceChangeItem> _items = [];
  bool _busy = false;

  // Reyonda okunan, eslesen kalem (foto bekliyor)
  PriceChangeItem? _matched;
  String? _scanMessage; // eslesmedi vb. uyari

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await PriceChangeService.instance.getActiveBatch();
    if (!mounted) return;
    setState(() {
      _items = items;
      _stage = items.isEmpty ? _Stage.empty : _Stage.apply;
    });
    if (_stage == _Stage.apply) await _scanner.start();
  }

  // ───────────────────────────── A4 OCR yukleme ──────────────────────
  Future<void> _captureA4() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (photo == null) return;

    setState(() {
      _busy = true;
      _stage = _Stage.loading;
    });

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(photo.path);
      final result = await recognizer.processImage(input);
      final batchId = DateTime.now().millisecondsSinceEpoch.toString();
      final parsed = PriceChangeParser.parse(result.text, batchId);

      if (parsed.isEmpty) {
        if (mounted) {
          setState(() {
            _busy = false;
            _stage = _items.isEmpty ? _Stage.empty : _Stage.apply;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Sayfadan veri okunamadı. Daha net/yakın çekmeyi deneyin.')),
          );
        }
        return;
      }

      // Coklu A4: bugune EKLE (eski liste silinmez).
      final added = await PriceChangeService.instance.addToToday(parsed);
      await _load();
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(added > 0
                ? '$added yeni ürün eklendi (toplam ${_items.length})'
                : 'Yeni ürün yok — hepsi zaten listede'),
            backgroundColor: AppTheme.statusSafe,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = _items.isEmpty ? _Stage.empty : _Stage.apply;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR hatası: $e')),
        );
      }
    } finally {
      recognizer.close();
    }
  }

  // ───────────────────────────── Reyon okutma ────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _matched != null) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    final parsed = ScanParser.parse(raw);
    final code = parsed.barcode;
    if (code == null) return;

    final item = await PriceChangeService.instance.findInActiveBatch(code);
    if (!mounted) return;
    if (item == null) {
      setState(() => _scanMessage = 'Bu barkod listede yok: $code');
      return;
    }
    if (item.changed) {
      setState(() =>
          _scanMessage = '${item.productName ?? code} zaten değiştirildi');
      return;
    }
    await _scanner.stop();
    setState(() {
      _matched = item;
      _scanMessage = null;
    });
  }

  /// Eslesen kaleme yeni etiket fotosu cek -> degistirildi isaretle.
  Future<void> _confirmChange() async {
    final item = _matched;
    if (item == null || item.id == null) return;
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo == null) return; // foto zorunlu; iptal edilirse isaretlenmez

    setState(() => _busy = true);
    await PriceChangeService.instance.markChanged(item.id!, photo.path);
    await _load();
    if (mounted) {
      setState(() {
        _matched = null;
        _busy = false;
      });
      await _scanner.start();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Değiştirildi: ${item.productName ?? item.barcode}'),
          backgroundColor: AppTheme.statusSafe,
          duration: const Duration(milliseconds: 1000),
        ),
      );
    }
  }

  Future<void> _cancelMatch() async {
    setState(() => _matched = null);
    await _scanner.start();
  }

  /// Bugunku tum listeyi sil (onayli).
  Future<void> _confirmClear() async {
    await _scanner.stop();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listeyi Sıfırla'),
        content: const Text(
            'Bugünkü tüm fiyat değişim kalemleri (tüm A4\'ler) silinecek. '
            'Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PriceChangeService.instance.clearActiveBatch();
      await _load();
    } else {
      await _scanner.start();
    }
  }

  // ───────────────────────────── Rapor ───────────────────────────────
  Future<void> _shareReport() async {
    final pending = _items.where((i) => !i.changed).toList();
    final done = _items.where((i) => i.changed).toList();
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    final buf = StringBuffer();
    buf.writeln('FİYAT DEĞİŞİM RAPORU');
    buf.writeln(fmt.format(DateTime.now()));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Fiyat Değişim'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_stage == _Stage.apply || _stage == _Stage.report)
            IconButton(
              icon: Icon(_stage == _Stage.report
                  ? Icons.qr_code_scanner_rounded
                  : Icons.assignment_turned_in_rounded),
              tooltip: _stage == _Stage.report ? 'Okutmaya Dön' : 'Rapor',
              onPressed: () async {
                if (_stage == _Stage.report) {
                  setState(() => _stage = _Stage.apply);
                  await _scanner.start();
                } else {
                  await _scanner.stop();
                  setState(() => _stage = _Stage.report);
                }
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _Stage.loading:
        return const LoadingState(message: 'İşleniyor...');
      case _Stage.empty:
        return _buildEmpty();
      case _Stage.apply:
        return _buildApply();
      case _Stage.report:
        return _buildReport();
    }
  }

  Widget _buildEmpty() {
    return EmptyState(
      icon: Icons.receipt_long_rounded,
      iconColor: AppTheme.amber,
      title: 'Fiyat Değişim Sayfası',
      subtitle:
          'İmzalı A4 fiyat değişim listesinin fotoğrafını çekin. '
          'Uygulama tablodaki ürünleri okuyup listeye çevirir, '
          'sonra reyonda etiketleri okutup değiştirdiğinizi işaretlersiniz.',
      action: FilledButton.icon(
        onPressed: _busy ? null : _captureA4,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('A4 Listeyi Tara'),
      ),
    );
  }

  Widget _buildApply() {
    final pending = _items.where((i) => !i.changed).length;
    final total = _items.length;
    return Column(
      children: [
        // Kamera
        SizedBox(
          height: 240,
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
                      color: AppTheme.statusExpired.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_scanMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ),
            ],
          ),
        ),

        // Eslesen kalem paneli (foto bekliyor)
        if (_matched != null) _buildMatchedPanel(),

        // Ilerleme + liste
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Kalan: $pending / $total',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary)),
              ),
              TextButton.icon(
                onPressed: _captureA4,
                icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                label: const Text('A4 Ekle'),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppTheme.textSecondary),
                onSelected: (v) {
                  if (v == 'clear') _confirmClear();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_rounded,
                            size: 18, color: AppTheme.statusExpired),
                        SizedBox(width: 8),
                        Text('Listeyi Sıfırla'),
                      ],
                    ),
                  ),
                ],
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WebSearchScreen(query: item.barcode),
            ),
          ),
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
                            decoration: item.changed
                                ? TextDecoration.none
                                : null,
                            color: item.changed
                                ? AppTheme.textSecondary
                                : AppTheme.textPrimary)),
                    Text(item.barcode,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppTheme.textTertiary)),
                  ],
                ),
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

  Widget _buildReport() {
    final pending = _items.where((i) => !i.changed).toList();
    final done = _items.where((i) => i.changed).toList();

    return Column(
      children: [
        // Ozet kartlari
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
                    count: done.length,
                    color: AppTheme.statusSafe,
                    icon: Icons.check_circle_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                    label: 'Kalan',
                    count: pending.length,
                    color: AppTheme.statusExpired,
                    icon: Icons.error_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text('Değiştirilmeyen Etiketler',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              FilledButton.icon(
                onPressed: _items.isEmpty ? null : _shareReport,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Paylaş'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: pending.isEmpty
              ? const EmptyState(
                  icon: Icons.task_alt_rounded,
                  iconColor: AppTheme.statusSafe,
                  title: 'Tüm etiketler değiştirildi',
                  subtitle: 'Bekleyen etiket kalmadı.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                  itemCount: pending.length,
                  itemBuilder: (_, i) {
                    final item = pending[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rLg),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WebSearchScreen(query: item.barcode),
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: AppTheme.card(
                            accentColor: AppTheme.statusExpired),
                        child: Row(
                          children: [
                            const Icon(Icons.label_off_rounded,
                                color: AppTheme.statusExpired, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName ?? item.barcode,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5)),
                                  Text(
                                      '${item.barcode}'
                                      '${item.aisle != null ? "  •  ${item.aisle}" : ""}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textTertiary)),
                                ],
                              ),
                            ),
                            if (item.newPrice != null)
                              Text(
                                  '${item.newPrice!.toStringAsFixed(2)} ₺',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.statusExpired)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
