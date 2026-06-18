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

      for (int i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.length < 2) continue;

        final barcodeCell = row[0]?.value?.toString().trim() ?? '';
        final nameCell = row[1]?.value?.toString().trim() ?? '';
        // 3. sutun: stok kodu (Excel: Barkod | Urun Adi | Stok Kodu | ...).
        final stockCell =
            row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';

        // Baslik satirini atla: bilinen anahtar kelimeler VEYA ilk satirda
        // barkod hucresi sayisal degilse (ornegin "Stok Kodu", "Urun No").
        if (i == 0) {
          final lower = barcodeCell.toLowerCase();
          final looksHeader = lower.contains('barkod') ||
              lower.contains('barcode') ||
              lower.contains('kod') ||
              lower.contains('stok') ||
              lower.contains('ürün') ||
              lower.contains('urun') ||
              !RegExp(r'\d').hasMatch(barcodeCell); // hic rakam yoksa baslik
          if (looksHeader) continue;
        }

        if (barcodeCell.isEmpty || nameCell.isEmpty) {
          if (barcodeCell.isNotEmpty || nameCell.isNotEmpty) {
            errors.add('Satır ${i + 1}: Eksik veri atlandı');
          }
          continue;
        }

        entries.add(BarcodeEntry(
          barcode: barcodeCell,
          productName: nameCell,
          stockCode: stockCell.isEmpty ? null : stockCell,
          importedAt: DateTime.now(),
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
                  const Icon(Icons.info_outline,
                      color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Excel Formatı',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'A sütunu: Barkod\nB sütunu: Ürün Adı\n\nBaşlık satırı opsiyonel. Mevcut barkodlar güncellenir.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Kayıtlı barkod: $_existingCount',
                        style: const TextStyle(color: AppTheme.textSecondary)),
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
                Text('Önizleme: ${_preview.length} kayıt — $_fileName',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
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
                        const Icon(Icons.qr_code,
                            size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 8),
                        Text(e.barcode,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13)),
                        const SizedBox(width: 12),
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
                  style: const TextStyle(
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
                      style: const TextStyle(
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
