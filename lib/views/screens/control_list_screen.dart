import 'dart:async';
import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/services/feedback_service.dart';
import '../widgets/scan_error_retry.dart';
import '../../core/camera_lifecycle_mixin.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/services/gemini_ocr_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../data/models/control_list_item.dart';
import '../../viewmodels/providers.dart';

/// ════════════════════════════════════════════════════════════════════
///  KONTROL LISTESI EKRANI
/// ────────────────────────────────────────────────────────────────────
///  Yonetici Excel (.xlsx) veya fotograf yukler. Fotograf Gemini'ye gider,
///  tabloya cevrilir. Cikan satirlar:
///    - control_list tablosuna (tum sutunlariyla, kalici)
///    - ayrica barcode_directory'ye (barkod + ad + stok kodu)
///  yazilir.
///
///  Kullanici listede bir urune dokununca/gecince, ALTTAKI kayan tarayici
///  panelinde o urunun barkodu otomatik internette aranir (hizli kontrol).
/// ════════════════════════════════════════════════════════════════════
class ControlListScreen extends ConsumerStatefulWidget {
  const ControlListScreen({super.key});

  @override
  ConsumerState<ControlListScreen> createState() => _ControlListScreenState();
}

class _ControlListScreenState extends ConsumerState<ControlListScreen> {
  List<ControlListItem> _items = [];
  bool _loading = false;
  String? _status;
  int? _selectedId; // su an secili (tarayicida aranan) urun

  // Alttaki gomulu tarayici
  WebViewController? _webController;
  bool _browserOpen = false;
  int _webProgress = 100;

  @override
  void initState() {
    super.initState();
    _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    final repo = ref.read(controlListRepositoryProvider);
    final items = await repo.getAll();
    if (mounted) setState(() => _items = items);
  }

  // ── EXCEL YUKLE ──
  Future<void> _importExcel() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final bytes = picked.files.first.bytes;
      if (bytes == null) {
        setState(() => _status = 'Dosya okunamadı');
        return;
      }
      setState(() {
        _loading = true;
        _status = 'Excel okunuyor...';
      });

      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.sheets[excel.sheets.keys.first]!;

      final parsed = _parseExcelRows(sheet);
      if (parsed.isEmpty) {
        setState(() {
          _loading = false;
          _status = 'Excel\'de uygun satır bulunamadı';
        });
        return;
      }
      await _saveItems(parsed, replaceAll: false);
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'Excel hatası: $e';
      });
    }
  }

  /// Excel satirlarini esnek baslik tanima ile ControlListItem'a cevirir.
  List<ControlListItem> _parseExcelRows(Sheet sheet) {
    if (sheet.rows.isEmpty) return [];

    // ── Hucre okuma yardimcilari (excel 4.x tipli deger API'si) ──
    String? cell(List<Data?> row, int? idx) {
      if (idx == null || idx >= row.length) return null;
      final v = row[idx]?.value;
      if (v == null) return null;
      // Sayisal hucreler tipli deger dondurur; barkod/stok kodu saf sayi
      // olabilir, .toString() "IntCellValue(...)" verir — gercek sayiyi al.
      String s;
      if (v is IntCellValue) {
        s = v.value.toString();
      } else if (v is DoubleCellValue) {
        final d = v.value;
        s = (d == d.truncateToDouble()) ? d.toInt().toString() : d.toString();
      } else if (v is TextCellValue) {
        s = v.value.toString().trim();
      } else {
        s = v.toString().trim();
        if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
      }
      s = s.trim();
      return s.isEmpty ? null : s;
    }

    int? cellInt(List<Data?> row, int? idx) {
      final s = cell(row, idx);
      if (s == null) return null;
      return int.tryParse(s.replaceAll(RegExp(r'[^0-9-]'), ''));
    }

    String headerText(Data? c) {
      final v = c?.value;
      if (v == null) return '';
      if (v is TextCellValue) return v.value.toString().toLowerCase().trim();
      return v.toString().toLowerCase().trim();
    }

    // ── Basliktan sutun indekslerini bul (esnek: sutun sirasi degisebilir) ──
    final header = sheet.rows.first;
    int? colSector,
        colCategory,
        colStockCode,
        colBarcode,
        colName,
        colStock,
        colRbg,
        colEntry,
        colSale;
    bool hasHeader = false;

    for (var i = 0; i < header.length; i++) {
      final raw = headerText(header[i]);
      if (raw.isEmpty) continue;
      if (raw.contains('sektör') || raw.contains('sektor')) {
        colSector = i;
        hasHeader = true;
      } else if (raw.contains('kategori')) {
        colCategory = i;
        hasHeader = true;
      } else if (raw.contains('stok kod')) {
        colStockCode = i;
        hasHeader = true;
      } else if (raw.contains('barkod')) {
        colBarcode = i;
        hasHeader = true;
      } else if (raw.contains('stok ad') || raw == 'ad') {
        colName = i;
        hasHeader = true;
      } else if (raw == 'stok' || raw.contains('stok mik')) {
        colStock = i;
        hasHeader = true;
      } else if (raw.contains('rbg')) {
        colRbg = i;
        hasHeader = true;
      } else if (raw.contains('son giriş') || raw.contains('son giris')) {
        colEntry = i;
        hasHeader = true;
      } else if (raw.contains('son satış') || raw.contains('son satis')) {
        colSale = i;
        hasHeader = true;
      }
    }

    // Baslik bulunamadiysa varsayilan sira (gorseldeki sıra).
    if (!hasHeader) {
      colSector = 0;
      colCategory = 1;
      colStockCode = 2;
      colBarcode = 3;
      colName = 4;
      colStock = 5;
      colRbg = 6;
      colEntry = 7;
      colSale = 8;
    }

    final now = DateTime.now();
    final items = <ControlListItem>[];
    for (var r = hasHeader ? 1 : 0; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      final barcode = cell(row, colBarcode);
      final name = cell(row, colName);
      if (barcode == null && name == null) continue;
      items.add(ControlListItem(
        sector: cell(row, colSector),
        category: cell(row, colCategory),
        stockCode: cell(row, colStockCode),
        barcode: barcode,
        productName: name,
        stock: cellInt(row, colStock),
        rbgDays: cellInt(row, colRbg),
        lastEntry: cell(row, colEntry),
        lastSale: cell(row, colSale),
        importedAt: now,
      ));
    }
    return items;
  }

  // ── FOTOGRAF YUKLE (Gemini) ──
  Future<void> _importPhotos() async {
    try {
      final hasKey = await GeminiOcrService.instance.hasApiKey();
      if (!hasKey) {
        setState(() => _status =
            'Gemini API anahtarı gerekli (Ayarlar\'dan ekleyin)');
        return;
      }
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage();
      if (picked.isEmpty) return;

      setState(() {
        _loading = true;
        _status = '${picked.length} fotoğraf Gemini ile okunuyor...';
      });

      final now = DateTime.now();
      final all = <ControlListItem>[];
      for (var i = 0; i < picked.length; i++) {
        setState(() => _status =
            'Fotoğraf ${i + 1}/${picked.length} okunuyor...');
        final rows = await GeminiOcrService.instance
            .extractStockTable(File(picked[i].path));
        for (final m in rows) {
          all.add(ControlListItem(
            sector: m['sector'] as String?,
            category: m['category'] as String?,
            stockCode: m['stockCode'] as String?,
            barcode: m['barcode'] as String?,
            productName: m['productName'] as String?,
            stock: m['stock'] as int?,
            rbgDays: m['rbgDays'] as int?,
            lastEntry: m['lastEntry'] as String?,
            lastSale: m['lastSale'] as String?,
            importedAt: now,
          ));
        }
      }
      if (all.isEmpty) {
        setState(() {
          _loading = false;
          _status = 'Fotoğraflarda satır bulunamadı';
        });
        return;
      }
      // MERGE: eski liste KORUNUR. Yeni foto/Excel mevcut urunleri gunceller
      // veya yenilerini ekler; eskileri SILMEZ (veri kaybi hatasinin koku).
      await _saveItems(all, replaceAll: false);
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'Fotoğraf okuma hatası: $e';
      });
    }
  }

  /// Cikan satirlari HEM control_list HEM barcode_directory'ye yazar.
  Future<void> _saveItems(List<ControlListItem> items,
      {required bool replaceAll}) async {
    final controlRepo = ref.read(controlListRepositoryProvider);
    final dirRepo = ref.read(barcodeDirectoryRepositoryProvider);

    // 1) Kontrol listesi tablosu.
    await controlRepo.insertItems(items, replaceAll: replaceAll);

    // 2) Barkod dizini: barkodu olan her satiri yaz (ad + stok kodu).
    //    Yonetici listesi guvenilir kabul edilir -> screen kaynagi +
    //    forceOverwrite (mevcut barcode_directory mantigiyla uyumlu olarak
    //    en guncel tanim olarak yazilir).
    final now = DateTime.now();
    final dirEntries = <BarcodeEntry>[];
    for (final it in items) {
      final bc = it.barcode?.trim();
      final name = it.productName?.trim();
      if (bc == null || bc.isEmpty || name == null || name.isEmpty) continue;
      dirEntries.add(BarcodeEntry(
        barcode: bc,
        productName: name,
        stockCode: it.stockCode?.trim(),
        importedAt: now,
        source: BarcodeSource.screen,
      ));
    }
    if (dirEntries.isNotEmpty) {
      await dirRepo.importAll(dirEntries, forceOverwrite: true);
    }

    await _loadFromDb();
    if (mounted) {
      setState(() {
        _loading = false;
        _status = '${items.length} ürün kaydedildi';
      });
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Listeyi Temizle'),
        content: const Text(
            'Kontrol listesindeki tüm ürünler silinsin mi? (Barkod dizinine yazılanlar kalır.)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Temizle')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(controlListRepositoryProvider).clearAll();
    await _loadFromDb();
    setState(() => _status = null);
  }

  // ════════════════════════════════════════════════════════════════════
  //  BARKOD TARAMA (KONTROL / ESLESTIRME)
  // ────────────────────────────────────────────────────────────────────
  //  Kullanici elindeki urunun barkodunu okutur. Okunan barkod kontrol
  //  listesinde aranir:
  //    • Listede VARSA  -> "Bu o urun" + urun adi gosterilir, satir
  //      'checked' (kontrol edildi) isaretlenir ve listede o satira kaydirilir.
  //    • Listede YOKSA  -> "Bu urun listede degil" uyarisi verilir.
  //  Boylece kullanici aradigi urunu elindeki urunle eslestirebilir.
  // ════════════════════════════════════════════════════════════════════
  Future<void> _scanToMatch() async {
    if (_items.isEmpty) {
      setState(() => _status = 'Once Excel/foto ile liste yukleyin.');
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _MatchScannerScreen()),
    );
    if (code == null || code.trim().isEmpty) return;
    final scanned = code.trim();

    // Listede bu barkodu ara (barkod birebir; bazi okuyucular bas/son
    // bosluk/sifir ekleyebildigi icin once birebir, sonra trim/sondaki
    // sifirsiz karsilastir).
    final idx = _items.indexWhere((e) {
      final b = e.barcode?.trim();
      if (b == null || b.isEmpty) return false;
      return b == scanned;
    });

    if (idx == -1) {
      // Listede yok.
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Eşleşme Yok'),
          content: Text(
              'Okutulan barkod ($scanned) kontrol listesinde bulunamadı.\n\n'
              'Bu ürün aradığınız ürün değil.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam')),
          ],
        ),
      );
      setState(() => _status = 'Barkod listede yok: $scanned');
      return;
    }

    // Eslesti: kontrol edildi isaretle + ekrani o satira getir.
    final matched = _items[idx];
    if (matched.id != null) {
      await ref.read(controlListRepositoryProvider).setChecked(matched.id!, true);
    }
    if (!mounted) return;
    setState(() {
      _items[idx] = matched.copyWith(checked: true);
      _selectedId = matched.id;
      _status = '✓ Eşleşti: ${matched.productName ?? scanned}';
    });

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✓ Eşleşti'),
        content: Text(
            '${matched.productName ?? "(isimsiz)"}\n\n'
            'Barkod: $scanned\n'
            '${matched.stockCode != null ? "Stok Kodu: ${matched.stockCode}\n" : ""}'
            'Bu, aradığınız üründür.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam')),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  PDF RAPOR
  // ────────────────────────────────────────────────────────────────────
  //  Yoneticinin attigi (atanan) kontrol listesi uzerinden ozet rapor:
  //    • Atanan toplam urun
  //    • Okutulan / kontrol edilen urun (checked)
  //    • Kalan (kontrol edilmemis) urun
  //  Ardindan tum urunler durum (✓ / -) ile listelenir. Yazdir/paylas
  //  menusu acilir.
  // ════════════════════════════════════════════════════════════════════
  Future<void> _generateReport() async {
    if (_items.isEmpty) {
      setState(() => _status = 'Rapor için liste boş.');
      return;
    }
    setState(() {
      _loading = true;
      _status = 'Rapor hazırlanıyor...';
    });

    try {
      final total = _items.length;
      final checked = _items.where((e) => e.checked).length;
      final remaining = total - checked;
      final now = DateTime.now();
      final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(now);

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
                  pw.Text('Kontrol Listesi Raporu',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Tarih: $dateStr',
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            // Ozet kutulari.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _pdfStat('Atanan', '$total', PdfColors.blue800),
                _pdfStat('Okutulan', '$checked', PdfColors.green800),
                _pdfStat('Kalan', '$remaining', PdfColors.orange800),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text('Ürün Listesi',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            // Tablo.
            pw.TableHelper.fromTextArray(
              headers: ['Durum', 'Ürün Adı', 'Barkod', 'Stok Kodu', 'RBG'],
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 9,
                  color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey700),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.center,
                4: pw.Alignment.center,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(36),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(1.4),
                4: const pw.FixedColumnWidth(36),
              },
              data: _items.map((e) {
                return [
                  e.checked ? '✓' : '-',
                  e.productName ?? '(isimsiz)',
                  e.barcode ?? '',
                  e.stockCode ?? '',
                  e.rbgDays?.toString() ?? '',
                ];
              }).toList(),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Rapor hazır';
      });
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'kontrol_raporu_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Rapor hatası: $e';
      });
    }
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
                    fontSize: 24, fontWeight: pw.FontWeight.bold, color: color)),
            pw.SizedBox(height: 2),
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Urune dokununca: alttaki tarayicida barkodu arat ──
  void _openInBrowser(ControlListItem item) {
    final query = (item.barcode?.isNotEmpty == true)
        ? item.barcode!
        : (item.productName ?? '');
    if (query.isEmpty) return;
    final url =
        'https://www.google.com/search?q=${Uri.encodeComponent(query)}';

    setState(() {
      _selectedId = item.id;
      _browserOpen = true;
      _webProgress = 0;
    });

    if (_webController == null) {
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              if (mounted) setState(() => _webProgress = p);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _webProgress = 100);
            },
          ),
        );
    }
    _webController!.loadRequest(Uri.parse(url));

    // Secili satiri kontrol edildi olarak isaretle.
    if (item.id != null) {
      ref.read(controlListRepositoryProvider).setChecked(item.id!, true);
      final idx = _items.indexWhere((e) => e.id == item.id);
      if (idx != -1) {
        setState(() => _items[idx] = _items[idx].copyWith(checked: true));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontrol Listesi'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Barkod okut (kontrol)',
            onPressed: _loading ? null : _scanToMatch,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'PDF rapor',
              onPressed: _loading ? null : _generateReport,
              icon: const Icon(Icons.picture_as_pdf_rounded),
            ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Listeyi temizle',
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          _toolbar(),
          if (_status != null) _statusBar(),
          Expanded(child: _listView()),
          if (_browserOpen) _browserPanel(),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: AppTheme.primary.withOpacity(0.06),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _importExcel,
              icon: const Icon(Icons.table_chart_rounded, size: 18),
              label: const Text('Excel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _importPhotos,
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: const Text('Fotoğraf'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.black.withOpacity(0.04),
      child: Row(
        children: [
          if (_loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_loading) const SizedBox(width: 10),
          Expanded(
            child: Text(_status!,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _listView() {
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fact_check_outlined,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Henüz liste yok.\nYöneticinin attığı Excel veya fotoğrafı yükleyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _itemTile(_items[i]),
    );
  }

  Widget _itemTile(ControlListItem item) {
    final selected = item.id != null && item.id == _selectedId;
    final rbg = item.rbgDays;
    // RBG (Rafta Bekleyen Gun) rengi: az gun = taze (yesil), cok gun = eski.
    Color rbgColor = Colors.grey;
    if (rbg != null) {
      if (rbg >= 6) {
        rbgColor = AppTheme.statusExpired;
      } else if (rbg >= 4) {
        rbgColor = AppTheme.statusCritical;
      } else if (rbg >= 2) {
        rbgColor = AppTheme.statusWarning;
      } else {
        rbgColor = AppTheme.statusSafe;
      }
    }

    return Material(
      color: selected ? AppTheme.primary.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: () => _openInBrowser(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.checked)
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 8),
                  child: Icon(Icons.check_circle,
                      size: 18, color: AppTheme.statusSafe),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.productName ?? '(isimsiz)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        if (item.barcode != null)
                          _meta('Barkod', item.barcode!),
                        if (item.stockCode != null)
                          _meta('Stok Kodu', item.stockCode!),
                        if (item.category != null)
                          _meta('Kategori', item.category!),
                      ],
                    ),
                    if (item.lastEntry != null || item.lastSale != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            if (item.lastEntry != null)
                              'Son Giriş: ${item.lastEntry}',
                            if (item.lastSale != null)
                              'Son Satış: ${item.lastSale}',
                          ].join('   •   '),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.stock != null)
                    Text('Stok: ${item.stock}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  if (rbg != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: rbgColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('RBG $rbg gün',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: rbgColor)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String label, String value) {
    return Text('$label: $value',
        style: const TextStyle(fontSize: 11, color: Colors.black54));
  }

  // ── ALTTAKI GOMULU KAYAN TARAYICI ──
  Widget _browserPanel() {
    final selected = _items.firstWhere(
      (e) => e.id == _selectedId,
      orElse: () => ControlListItem(importedAt: DateTime.now()),
    );
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.42,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.public_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected.barcode ?? selected.productName ?? 'Arama',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Tarayıcıyı kapat',
                  onPressed: () => setState(() {
                    _browserOpen = false;
                    _selectedId = null;
                  }),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  iconSize: 20,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          if (_webProgress < 100)
            LinearProgressIndicator(
              value: _webProgress / 100,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: AppTheme.primary,
            ),
          Expanded(
            child: _webController == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _webController!),
          ),
        ],
      ),
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  BARKOD ESLESTIRME TARAYICISI
/// ────────────────────────────────────────────────────────────────────
///  Tek amac: bir barkod okutup geri dondurmek. Okunan ilk gecerli
///  barkod Navigator.pop ile string olarak doner. Cagiran ekran (kontrol
///  listesi) bunu listede arar.
/// ════════════════════════════════════════════════════════════════════
class _MatchScannerScreen extends StatefulWidget {
  const _MatchScannerScreen();

  @override
  State<_MatchScannerScreen> createState() => _MatchScannerScreenState();
}

class _MatchScannerScreenState extends State<_MatchScannerScreen> with CameraLifecycleMixin {
  // Kamera yasam dongusu: arka plandan donunce kamera unlem/takilma
  // yasamasin diye durdur/yeniden baslat.
  @override
  List<MobileScannerController> get cameraControllers => [_controller];
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        HapticFeedback.mediumImpact();
        FeedbackService.instance.play(ScanFeedback.product);
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Barkod Okut'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect, errorBuilder: (context, error, child) => ScanErrorRetry(controller: _controller)),
          // Hedef cercevesi.
          Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Text(
              'Ürünün barkodunu çerçeveye getirin',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
