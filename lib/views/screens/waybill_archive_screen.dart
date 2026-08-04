import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/waybill_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// ════════════════════════════════════════════════════════════════════
///  İRSALİYE ARŞİVİ (v150)
///  Gecmiste uretilen TUM palet transfer PDF'leri burada listelenir.
///  Dosyalar <belgeler>/waybills altinda durur; ek veritabani yok —
///  dosya adindan palet kodu ve tarih cozulur.
/// ════════════════════════════════════════════════════════════════════
class WaybillArchiveScreen extends StatefulWidget {
  const WaybillArchiveScreen({super.key});
  @override
  State<WaybillArchiveScreen> createState() => _WaybillArchiveScreenState();
}

class _WaybillArchiveScreenState extends State<WaybillArchiveScreen> {
  List<WaybillFile> _files = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await WaybillService.instance.listSaved();
    if (!mounted) return;
    setState(() {
      _files = f;
      _loading = false;
    });
  }

  List<WaybillFile> get _filtered {
    if (_query.trim().isEmpty) return _files;
    final q = _query.trim().toLowerCase();
    return _files
        .where((f) => f.palletCode.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _delete(WaybillFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İrsaliye silinsin mi?'),
        content: Text('${f.palletCode} · '
            '${DateFormat('dd.MM.yyyy HH:mm').format(f.date)}\n\n'
            'PDF dosyası cihazdan silinecek.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await WaybillService.instance.deleteSaved(f.path);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _hero(),
          if (_files.length > 4) _searchBar(),
          Expanded(
            child: _loading
                ? const SkeletonList()
                : list.isEmpty
                    ? EmptyState(
                        icon: Icons.picture_as_pdf_rounded,
                        title: _files.isEmpty
                            ? 'Henüz irsaliye yok'
                            : 'Eşleşen kayıt yok',
                        subtitle: _files.isEmpty
                            ? 'Palet transferi yaptığında oluşan irsaliye '
                                'PDF’leri burada birikir.'
                            : 'Farklı bir palet kodu deneyin.',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 10, 16,
                            MediaQuery.of(context).padding.bottom + 24),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _card(list[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(8, topPad + 6, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent,
            Color.lerp(AppTheme.accent, AppTheme.primary, 0.55)!,
          ],
        ),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(AppTheme.rLg)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          ),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded,
                size: 19, color: Colors.black),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transfer İrsaliyeleri',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.black)),
                Text(
                    _loading
                        ? 'yükleniyor…'
                        : '${_files.length} kayıtlı PDF',
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black87)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Yenile',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Palet kodu ara',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: AppTheme.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _card(WaybillFile f) {
    final dateStr = DateFormat('dd.MM.yyyy · HH:mm').format(f.date);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.card(accentColor: AppTheme.primary),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.description_rounded,
                color: AppTheme.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.palletCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
                Text('$dateStr · ${f.sizeLabel}',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Aç / Yazdır',
            visualDensity: VisualDensity.compact,
            onPressed: () => WaybillService.instance.printSaved(f.path),
            icon: Icon(Icons.open_in_new_rounded,
                size: 19, color: AppTheme.primary),
          ),
          IconButton(
            tooltip: 'Paylaş',
            visualDensity: VisualDensity.compact,
            onPressed: () => WaybillService.instance.sharePdf(f.path),
            icon: Icon(Icons.ios_share_rounded,
                size: 19, color: AppTheme.accent),
          ),
          IconButton(
            tooltip: 'Sil',
            visualDensity: VisualDensity.compact,
            onPressed: () => _delete(f),
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}
