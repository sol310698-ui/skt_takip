import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/barcode_entry.dart';
import '../../viewmodels/providers.dart';

/// Excel'den barkod + urun adi import ekrani.
/// Beklenen format: A = barkod, B = urun adi
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _loading = false;
  bool _saving = false;
  List<BarcodeEntry> _preview = [];
  List<String> _errors = [];
  String? _fileName;
  int _existingCount = 0;

  /// excel 4.x hucre degerini guvenli sekilde stringe cevirir.
  /// Sayisal hucreler (IntCellValue/DoubleCellValue) icin gercek sayiyi alir;
  /// metin ve diger tipler icin onceki calisan davranisi korur.
  String _cellToString(dynamic cell) {
    if (cell == null) return '';
    final v = cell.value;
    if (v == null) return '';
    // SAYISAL hucreler: stok kodu/barkod saf sayi olabilir.
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      if (d == d.truncateToDouble()) return d.toInt().toString();
      return d.toString();
    }
    // Metin ve diger tipler: onceki calisan yontem (.toString()).
    var s = v.toString().trim();
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await ref
        .read(barcodeDirectoryRepositoryProvider)
        .count();
    if (mounted) setState(() => _existingCount = count);
  }

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _preview = [];
      _errors = [];
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _loading = false;
          _errors = ['Dosya okunamadı'];
        });
        return;
      }

      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.sheets.keys.first;
      final sheet = excel.sheets[sheetName]!;

      final entries = <BarcodeEntry>[];
      final errors = <String>[];

      // ── SUTUN KONUMLARINI BASLIKTAN BUL ──
      // Excel'de sutun sirasi degisebilir. Ilk satir baslik ise, basliktaki
      // anahtar kelimelere gore barkod/ad/stok kodu sutununu DINAMIK buluruz.
      // Baslik yoksa varsayilan sira kullanilir: A=barkod, B=ad, C=stok kodu.
      int barcodeCol = 0;
      int nameCol = 1;
      int stockCol = 2;
      int startRow = 0;

      if (sheet.rows.isNotEmpty) {
        final first = sheet.rows.first;
        // Basliktaki her hucreyi kucuk harfe cevirip anahtar kelime ara.
        final headers = <String>[];
        for (final c in first) {
          headers.add(_cellToString(c).toLowerCase());
        }
        // Bu satir gercekten baslik mi? (barkod hucresi rakam icermiyorsa
        // veya bilinen baslik kelimeleri varsa.)
        final looksHeader = headers.any((h) =>
            h.contains('barkod') ||
            h.contains('barcode') ||
            h.contains('stok') ||
            h.contains('kod') ||
            h.contains('ürün') ||
            h.contains('urun') ||
            h.contains('ad'));

        if (looksHeader) {
          startRow = 1; // baslik satirini atla
          for (int c = 0; c < headers.length; c++) {
            final h = headers[c];
            // "stok kodu" -> stok kodu sutunu (once bunu kontrol et:
            // "stok adı" ile karismasin diye 'kod' sart).
            if (h.contains('kod') &&
                !h.contains('barkod') &&
                !h.contains('barcode')) {
              stockCol = c;
            } else if (h.contains('barkod') || h.contains('barcode')) {
              barcodeCol = c;
            } else if (h.contains('ad') ||
                h.contains('ürün') ||
                h.contains('urun') ||
                h.contains('isim')) {
              nameCol = c;
            }
          }
        }
      }

      for (int i = startRow; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        String cellAt(int idx) =>
            _cellToString(idx < row.length ? row[idx] : null);

        final barcodeCell = cellAt(barcodeCol);
        final nameCell = cellAt(nameCol);
        final stockCell = cellAt(stockCol);
        final barcodeClean = barcodeCell;

        // startRow=0 (baslik yok) iken ilk satir yanlislikla baslik olabilir:
        // barkod hucresinde hic rakam yoksa atla.
        if (i == 0 && !RegExp(r'\d').hasMatch(barcodeCell)) {
          continue;
        }

        if (barcodeCell.isEmpty || nameCell.isEmpty) {
          if (barcodeCell.isNotEmpty || nameCell.isNotEmpty) {
            errors.add('Satır ${i + 1}: Eksik veri atlandı');
          }
          continue;
        }

        entries.add(BarcodeEntry(
          barcode: barcodeClean,
          productName: nameCell,
          stockCode: stockCell.isEmpty ? null : stockCell,
          importedAt: DateTime.now(),
          source: BarcodeSource.excel,
        ));
      }

      setState(() {
        _loading = false;
        _preview = entries;
        _errors = errors;
        _fileName = file.name;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errors = ['Dosya okunurken hata: $e'];
      });
    }
  }

  Future<void> _import() async {
    if (_preview.isEmpty) return;
    setState(() => _saving = true);

    try {
      await ref
          .read(barcodeDirectoryRepositoryProvider)
          .importAll(_preview);
      await _loadCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_preview.length} kayıt içe aktarıldı'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _preview = [];
          _errors = [];
          _fileName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Temizle'),
        content: const Text('Tüm barkod dizini silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(barcodeDirectoryRepositoryProvider).clearAll();
      await _loadCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excel Import')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Bilgi karti
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glassCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Excel Formatı',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'A sütunu: Barkod\nB sütunu: Ürün Adı\nC sütunu: Stok Kodu (opsiyonel)\n\nBaşlık satırı opsiyonel. Excel verileri en güvenilir kaynaktır ve internetten gelen bilgilerin üzerine yazar.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Kayıtlı barkod: $_existingCount',
                        style: TextStyle(color: AppTheme.textSecondary)),
                    if (_existingCount > 0)
                      TextButton(
                        onPressed: _clearAll,
                        child: const Text('Temizle',
                            style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loading ? null : _pickFile,
            icon: _loading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.upload_file),
            label: Text(_loading ? 'Okunuyor...' : 'Excel Dosyası Seç'),
          ),

          // Önizleme
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Önizleme: ${_preview.length} kayıt — $_fileName',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Kac kayitta stok kodu okundu? (Ice aktarmadan once teyit.)
            Builder(builder: (_) {
              final withStock = _preview
                  .where((e) =>
                      e.stockCode != null && e.stockCode!.isNotEmpty)
                  .length;
              final ok = withStock == _preview.length;
              return Row(
                children: [
                  Icon(
                    ok
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: ok ? AppTheme.statusSafe : AppTheme.statusWarning,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Stok kodu okunan: $withStock / ${_preview.length}',
                    style: TextStyle(
                        color: ok
                            ? AppTheme.statusSafe
                            : AppTheme.statusWarning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              );
            }),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: AppTheme.glassCard(),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: _preview.length > 50 ? 50 : _preview.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = _preview[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code,
                            size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 8),
                        Text(e.barcode,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13)),
                        const SizedBox(width: 8),
                        // Stok kodu okunduysa goster (yesil etiket).
                        if (e.stockCode != null && e.stockCode!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.statusSafe.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('#${e.stockCode}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.statusSafe)),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_preview.length > 50)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '... ve ${_preview.length - 50} kayıt daha',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _import,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text('${_preview.length} Kaydı İçe Aktar'),
            ),
          ],

          // Hatalar
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: AppTheme.glassCard(
                  accent: Colors.orange),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Uyarılar',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ..._errors.map((e) => Text(e,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
