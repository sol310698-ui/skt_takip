import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'warehouse_service.dart';

/// Palet irsaliyesi PDF olusturucu.
/// QR: pdf paketinin BarcodeWidget ile uretilir — ekstra paket gerektirmez.
class WaybillService {
  WaybillService._();
  static final WaybillService instance = WaybillService._();

  // ── TURKCE KARAKTER: gomulu Noto Sans fontu ──────────────────────────
  // PDF paketinin varsayilan fontu (Helvetica) Turkce harfleri (İ, ş, ğ,
  // ı) BOZUK gosterir. Uygulamaya gomulu Noto Sans ile tum PDF/etiketler
  // Turkce uyumlu uretilir. Font bir kez yuklenip onbelleklenir.
  static pw.Font? _fontReg;
  static pw.Font? _fontBold;

  static Future<pw.ThemeData> _theme() async {
    try {
      _fontReg ??=
          pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      _fontBold ??=
          pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      return pw.ThemeData.withFont(base: _fontReg!, bold: _fontBold!);
    } catch (_) {
      // Font yuklenemezse cokme; varsayilan tema (Turkce eksik olabilir).
      return pw.ThemeData();
    }
  }

  /// PDF olustur, kalici klasore kaydet, yolunu dondur.
  Future<String> generateWaybill({
    required WhPallet pallet,
    required List<WhPalletItem> items,
    required WhTransfer transfer,
  }) async {
    final pdf = pw.Document(theme: await _theme());
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    final dateStr = fmt.format(transfer.createdAt);
    final isExternal = transfer.transferType == 'external';

    final qrData = 'PALET:${pallet.code}'
        '|ID:${pallet.id}'
        '|TARIH:${transfer.createdAt.millisecondsSinceEpoch}'
        '${isExternal ? "|HEDEF:${transfer.toExternalName ?? ""}" : ""}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // BASLIK
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        isExternal
                            ? 'SEVK İRSALİYESİ'
                            : 'TRANSFER İRSALİYESİ',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Tarih: $dateStr',
                          style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('Palet: ${pallet.code}',
                          style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                // QR kod
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrData,
                  width: 90,
                  height: 90,
                ),
              ],
            ),
            pw.Divider(thickness: 1.5),

            // KAYNAK / HEDEF
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoBox('CIKIS', [
                  transfer.fromWarehouseName ?? 'Bilinmiyor',
                  if (transfer.fromShelfLabel != null)
                    'Raf: ${transfer.fromShelfLabel}',
                ]),
                pw.SizedBox(width: 16),
                pw.Center(
                  child: pw.Text('->',
                      style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(width: 16),
                _infoBox(
                  'VARIS',
                  isExternal
                      ? [
                          transfer.toExternalName ?? 'Belirtilmedi',
                          if (transfer.toExternalAddress != null &&
                              transfer.toExternalAddress!.isNotEmpty)
                            transfer.toExternalAddress!,
                        ]
                      : [
                          transfer.toWarehouseName ?? 'Ayni Depo',
                          if (transfer.toShelfLabel != null)
                            'Raf: ${transfer.toShelfLabel}',
                        ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            if (transfer.note != null && transfer.note!.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(children: [
                  pw.Text('Not: ',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Expanded(
                    child: pw.Text(transfer.note!,
                        style: const pw.TextStyle(fontSize: 11)),
                  ),
                ]),
              ),
              pw.SizedBox(height: 12),
            ],

            // URUN LISTESI
            pw.Text('URUN LiSTESi',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.6),
                1: pw.FlexColumnWidth(4),
                2: pw.FlexColumnWidth(2.2),
                3: pw.FlexColumnWidth(0.8),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('#', bold: true),
                    _cell('Urun Adi', bold: true),
                    _cell('Barkod', bold: true),
                    _cell('Adet', bold: true),
                  ],
                ),
                ...items.asMap().entries.map((e) => pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: e.key.isEven
                            ? PdfColors.white
                            : PdfColors.grey50,
                      ),
                      children: [
                        _cell('${e.key + 1}'),
                        _cell(e.value.productName ?? '-'),
                        _cell(e.value.barcode),
                        _cell('${e.value.quantity}'),
                      ],
                    )),
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell(''),
                    _cell('TOPLAM', bold: true),
                    _cell(''),
                    _cell(
                        '${items.fold(0, (s, i) => s + i.quantity)}',
                        bold: true),
                  ],
                ),
              ],
            ),
            pw.Spacer(),

            // IMZA ALANLARI
            pw.Divider(),
            pw.Row(
              children: [
                pw.Expanded(child: _signBox('Teslim Eden')),
                pw.SizedBox(width: 40),
                pw.Expanded(child: _signBox('Teslim Alan')),
              ],
            ),
          ],
        ),
      ),
    );

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/waybills');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final fname =
        'irsaliye_${pallet.code}_${transfer.createdAt.millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fname');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  IRSALIYE ARSIVI (v150)
  ///  Uretilen tum transfer PDF'leri <belgeler>/waybills altinda durur.
  ///  Dosya adi: irsaliye_<paletKodu>_<zamanDamgasi>.pdf — palet kodu ve
  ///  tarih buradan cozulur (ek veritabani gerekmez).
  /// ══════════════════════════════════════════════════════════════════
  Future<List<WaybillFile>> listSaved() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/waybills');
    if (!dir.existsSync()) return const [];
    final out = <WaybillFile>[];
    for (final f in dir.listSync()) {
      if (f is! File || !f.path.toLowerCase().endsWith('.pdf')) continue;
      final name = f.path.split('/').last;
      String code = '—';
      DateTime date;
      try {
        // irsaliye_<kod>_<ms>.pdf  (kodun icinde '_' olabilir)
        final base = name.substring(0, name.length - 4); // .pdf at
        final parts = base.split('_');
        final ms = int.tryParse(parts.last);
        date = ms != null
            ? DateTime.fromMillisecondsSinceEpoch(ms)
            : f.statSync().modified;
        if (parts.length >= 3) {
          code = parts.sublist(1, parts.length - 1).join('_');
        }
      } catch (_) {
        date = f.statSync().modified;
      }
      out.add(WaybillFile(
        path: f.path,
        palletCode: code,
        date: date,
        sizeBytes: f.statSync().size,
      ));
    }
    // En yeni ustte.
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> deleteSaved(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }

  /// Kayitli PDF'i sistem onizleme/yazdirma diyaloguyla acar.
  Future<void> printSaved(String path) async {
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(
      name: path.split('/').last,
      onLayout: (_) async => bytes,
    );
  }

  Future<void> sharePdf(String path) async {
    await Printing.sharePdf(
      bytes: await File(path).readAsBytes(),
      filename: path.split('/').last,
    );
  }

  // ── PALET QR ETIKETI (paletin disina yazicidan basilir) ──────────────
  // QR icerigi irsaliyedekiyle uyumlu: 'PALET:<kod>|ID:<id>'. Iki boyut:
  //   • detailed=true  -> A4: buyuk QR + kod (+ urun ozeti). Normal yazici.
  //   • detailed=false -> kucuk etiket (~62x60mm). Termal/etiket yazicisi.
  Future<Uint8List> buildPalletQrLabel({
    required WhPallet pallet,
    required PdfPageFormat format,
    bool detailed = false,
    String? productSummary,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final qrData = 'PALET:${pallet.code}|ID:${pallet.id}';
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(detailed ? 28 : 8),
        build: (ctx) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: detailed ? 240 : 120,
                height: detailed ? 240 : 120,
              ),
              pw.SizedBox(height: detailed ? 18 : 6),
              pw.Text(
                pallet.code,
                style: pw.TextStyle(
                    fontSize: detailed ? 30 : 15,
                    fontWeight: pw.FontWeight.bold),
              ),
              if (detailed &&
                  productSummary != null &&
                  productSummary.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text(
                  productSummary,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  /// ══════════════════════════════════════════════════════════════════
  ///  A4 PALET FISI (v150) — palet QR + urunlerin YANINDA okunabilir
  ///  BARKOD. Kagidi el terminaliyle okutup is yapmak icin: her satirda
  ///  urun adi, adet ve taranabilir barkod var. Urun cok ise sayfalara
  ///  bolunur (MultiPage).
  /// ══════════════════════════════════════════════════════════════════
  Future<Uint8List> buildPalletSheet({
    required WhPallet pallet,
    required List<WhPalletItem> items,
    String? locationLabel,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    final qrData = 'PALET:${pallet.code}|ID:${pallet.id}';
    final totalQty = items.fold<int>(0, (t, e) => t + e.quantity);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text('${pallet.code} (devam)',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Sayfa ${ctx.pageNumber}/${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9)),
        ),
        build: (ctx) => [
          // ── BASLIK: QR + palet bilgisi ──
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: 92,
                height: 92,
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(pallet.code,
                        style: pw.TextStyle(
                            fontSize: 26, fontWeight: pw.FontWeight.bold)),
                    if (locationLabel != null && locationLabel.isNotEmpty)
                      pw.Text(locationLabel,
                          style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                        '${items.length} çeşit · $totalQty adet',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text('Yazdırma: ${fmt.format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 4),
          // ── URUN SATIRLARI: ad + adet + TARANABILIR BARKOD ──
          if (items.isEmpty)
            pw.Text('Bu palette ürün yok.',
                style: const pw.TextStyle(fontSize: 12))
          else
            ...List.generate(items.length, (i) {
              final it = items[i];
              return pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 7),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.SizedBox(
                      width: 18,
                      child: pw.Text('${i + 1}',
                          style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            it.productName ?? it.barcode,
                            maxLines: 2,
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text('${it.quantity} adet',
                              style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    // Terminalden okunacak barkod.
                    pw.BarcodeWidget(
                      barcode: _barcodeFor(it.barcode),
                      data: it.barcode,
                      width: 150,
                      height: 42,
                      drawText: true,
                      textStyle: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> printPalletSheet({
    required WhPallet pallet,
    required List<WhPalletItem> items,
    String? locationLabel,
  }) async {
    await Printing.layoutPdf(
      name: 'palet_${pallet.code}_urunler',
      onLayout: (_) => buildPalletSheet(
        pallet: pallet,
        items: items,
        locationLabel: locationLabel,
      ),
    );
  }

  /// Barkod tipini SECER: gecerli EAN-13 / UPC-A ise onu, degilse
  /// Code128 (her el terminali okur). Gecersiz veriyle EAN cizmek
  /// PDF uretimini patlatir — bu yuzden once dogrulanir.
  static pw.Barcode _barcodeFor(String raw) {
    final v = raw.trim();
    if (RegExp(r'^\d{13}$').hasMatch(v) && _eanChecksumOk(v)) {
      return pw.Barcode.ean13();
    }
    if (RegExp(r'^\d{12}$').hasMatch(v) && _eanChecksumOk('0$v')) {
      return pw.Barcode.upcA();
    }
    return pw.Barcode.code128();
  }

  /// EAN-13 kontrol hanesi dogrulamasi.
  static bool _eanChecksumOk(String v) {
    if (v.length != 13) return false;
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = int.tryParse(v[i]);
      if (d == null) return false;
      sum += (i % 2 == 0) ? d : d * 3;
    }
    final check = (10 - (sum % 10)) % 10;
    return check == int.tryParse(v[12]);
  }

  /// Palet QR etiketini SISTEM YAZICI diyaloguyla yazdirir (paylasim degil).
  Future<void> printPalletQrLabel({
    required WhPallet pallet,
    required PdfPageFormat format,
    bool detailed = false,
    String? productSummary,
  }) async {
    await Printing.layoutPdf(
      name: 'palet_${pallet.code}_qr',
      onLayout: (_) => buildPalletQrLabel(
        pallet: pallet,
        format: format,
        detailed: detailed,
        productSummary: productSummary,
      ),
    );
  }

  /// A4 boyutta buyuk QR etiketi (normal yazici) — urun ozeti dahil.
  Future<void> printPalletQrA4(WhPallet pallet, {String? productSummary}) =>
      printPalletQrLabel(
        pallet: pallet,
        format: PdfPageFormat.a4,
        detailed: true,
        productSummary: productSummary,
      );

  /// Kucuk etiket (~62x60mm) — termal/etiket yazicisi.
  Future<void> printPalletQrSmall(WhPallet pallet) => printPalletQrLabel(
        pallet: pallet,
        format: const PdfPageFormat(62 * PdfPageFormat.mm, 60 * PdfPageFormat.mm),
        detailed: false,
      );

  pw.Widget _infoBox(String title, List<String> lines) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                      color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              ...lines.map((l) =>
                  pw.Text(l, style: const pw.TextStyle(fontSize: 11))),
            ],
          ),
        ),
      );

  pw.Widget _signBox(String label) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 28),
          pw.Container(height: 1, color: PdfColors.grey400),
          pw.Text('Ad / imza',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
        ],
      );

  pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight:
                bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
        ),
      );
}


/// Arsivdeki tek bir irsaliye PDF'i.
class WaybillFile {
  final String path;
  final String palletCode;
  final DateTime date;
  final int sizeBytes;
  const WaybillFile({
    required this.path,
    required this.palletCode,
    required this.date,
    required this.sizeBytes,
  });

  String get sizeLabel => sizeBytes < 1024
      ? '$sizeBytes B'
      : sizeBytes < 1024 * 1024
          ? '${(sizeBytes / 1024).toStringAsFixed(0)} KB'
          : '${(sizeBytes / 1048576).toStringAsFixed(1)} MB';
}


