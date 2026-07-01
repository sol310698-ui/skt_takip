import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/scroll_to_top_fab.dart';

/// Uygulama/alarm kayitlarini (log) goruntuleyen, paylasan ekran.
/// Kullanici buradaki metni kopyalayip veya paylasarak destek icin iletebilir.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _content = 'Yükleniyor...';
  bool _loading = true;
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';

  /// Arama filtresine gore gorunen log satirlari. Bos filtrede tum icerik.
  String get _visibleContent {
    if (_filter.isEmpty) return _content;
    final lower = _filter.toLowerCase();
    final lines = _content
        .split('\n')
        .where((l) => l.toLowerCase().contains(lower))
        .toList();
    return lines.isEmpty ? '(Eşleşen kayıt yok: "$_filter")' : lines.join('\n');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final c = await AppLogger.instance.readAll();
    if (!mounted) return;
    setState(() {
      _content = c;
      _loading = false;
    });
  }

  Future<void> _share() async {
    try {
      final path = await AppLogger.instance.filePath();
      await Share.shareXFiles(
        [XFile(path)],
        text: 'SKT Takip alarm kayıtları',
      );
    } catch (_) {
      // Dosya paylasimi olmazsa metni paylas.
      await Share.share(_content, subject: 'SKT Takip alarm kayıtları');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kayıtlar panoya kopyalandı'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kayıtları Temizle'),
        content: const Text('Tüm log kayıtları silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Temizle')),
        ],
      ),
    );
    if (ok == true) {
      await AppLogger.instance.clear();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Uygulama Kayıtları (Log)'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'Paylaş',
            icon: const Icon(Icons.share_rounded),
            onPressed: _share,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: AppTheme.primary.withOpacity(0.1),
                      child: const Text(
                        'Uygulamanın tüm kayıtları (olaylar, hatalar, alarm). '
                        'Bir sorunu bildirmek için sağ üstten "Paylaş" ile '
                        'gönderin. Aşağıdaki kutuyla arama yapabilirsiniz.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _filter = v.trim()),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Ara (ör. HATA, ALARM, barkod...)',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _filter.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _filter = '');
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _visibleContent,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Nav bar olmayan tam sayfa ekran: sadece scroll esigine
                // gore calisir.
                ScrollToTopFab(
                  controller: _scrollCtrl,
                  syncWithNavBar: false,
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Kopyala'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Temizle'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.statusExpired,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
