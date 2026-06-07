import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/product.dart';

/// Excel export servisi.
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  /// Aktif urunler + imha/iade gecmisini Excel olarak disa aktar.
  Future<void> exportToExcel({
    required List<Product> activeProducts,
    required List<Product> historyProducts,
  }) async {
    final excel = Excel.createExcel();

    // --- Aktif Urunler sayfasi ---
    final activeSheet = excel['Aktif Ürünler'];
    excel.setDefaultSheet('Aktif Ürünler');

    _writeRow(activeSheet, 0, [
      'Ürün Adı', 'Barkod', 'SKT', 'Kalan Gün',
      'Durum', 'Adet', 'Kategori',
    ], header: true);

    for (int i = 0; i < activeProducts.length; i++) {
      final p = activeProducts[i];
      _writeRow(activeSheet, i + 1, [
        p.name,
        p.barcode ?? '',
        DateFormat('dd.MM.yyyy').format(p.expiryDate),
        p.daysUntilExpiry.toString(),
        p.status.label,
        p.quantity.toString(),
        p.category ?? '',
      ]);
    }

    // --- Imha / Iade sayfasi ---
    final histSheet = excel['İmha & İade Geçmişi'];
    _writeRow(histSheet, 0, [
      'Ürün Adı', 'Barkod', 'SKT', 'İşlem',
      'İşlem Tarihi', 'Not', 'Kategori',
    ], header: true);

    for (int i = 0; i < historyProducts.length; i++) {
      final p = historyProducts[i];
      _writeRow(histSheet, i + 1, [
        p.name,
        p.barcode ?? '',
        DateFormat('dd.MM.yyyy').format(p.expiryDate),
        p.disposalStatus.label,
        p.disposalDate != null
            ? DateFormat('dd.MM.yyyy').format(p.disposalDate!)
            : '',
        p.disposalNote ?? '',
        p.category ?? '',
      ]);
    }

    // Varsayilan bos sayfayi sil.
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Dosyaya yaz.
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Excel encode hatası');

    final dir = await getTemporaryDirectory();
    final dateStr = DateFormat('dd_MM_yyyy').format(DateTime.now());
    final file = File('${dir.path}/SKT_Raporu_$dateStr.xlsx');
    await file.writeAsBytes(bytes);

    // Paylas.
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'SKT Raporu $dateStr',
    );
  }

  void _writeRow(
    Sheet sheet,
    int row,
    List<String> values, {
    bool header = false,
  }) {
    for (int col = 0; col < values.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: row,
      ));
      cell.value = TextCellValue(values[col]);
      if (header) {
        cell.cellStyle = CellStyle(bold: true);
      }
    }
  }
}
