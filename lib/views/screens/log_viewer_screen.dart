import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/app_logger.dart';
import '../../core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
        title: const Text('Alarm Kayıtları (Log)'),
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
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: AppTheme.primary.withOpacity(0.1),
                  child: const Text(
                    'Alarm sorununu çözmek için: alarmı test edip çaldıktan '
                    '(veya çalması gerekip çalmadıktan) sonra bu ekranı açıp '
                    'sağ üstten "Paylaş" ile kayıtları gönderin.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _content,
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
