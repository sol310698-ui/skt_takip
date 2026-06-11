import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/gemini_ocr_service.dart';
import '../../core/services/price_change_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'price_change_session_screen.dart';

/// Fiyat Degisim — Oturum listesi.
/// Her oturum bir KART: tarih, ilerleme, durum. Karta dokun -> detay.
class PriceChangeScreen extends StatefulWidget {
  const PriceChangeScreen({super.key});

  @override
  State<PriceChangeScreen> createState() => _PriceChangeScreenState();
}

class _PriceChangeScreenState extends State<PriceChangeScreen> {
  List<SessionSummary> _sessions = [];
  bool _loading = true;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await PriceChangeService.instance.getSessions();
    final hasKey = await GeminiOcrService.instance.hasApiKey();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _hasKey = hasKey;
      _loading = false;
    });
  }

  Future<void> _newSession() async {
    final id = await PriceChangeService.instance.createSession();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PriceChangeSessionScreen(sessionId: id)),
    );
    _load();
  }

  Future<void> _openSession(SessionSummary s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              PriceChangeSessionScreen(sessionId: s.session.id!)),
    );
    _load();
  }

  Future<void> _deleteSession(SessionSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oturumu Sil'),
        content: Text(
            '${DateFormat('dd.MM.yyyy').format(s.session.createdAt)} oturumu '
            've ${s.total} kalemi silinecek. (Kanıt fotoğrafları silinmez.) '
            'Emin misiniz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.statusExpired),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PriceChangeService.instance.deleteSession(s.session.id!);
      _load();
    }
  }

  /// Gemini API anahtari ayar dialogu.
  Future<void> _openKeySettings() async {
    final current = await GeminiOcrService.instance.getApiKey();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Online OCR (Gemini)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A4 tablolarını yüksek doğrulukla okumak için Gemini API '
              'anahtarı gerekir. Ücretsiz: aistudio.google.com → '
              '"Get API key". Anahtar cihazda şifreli saklanır.',
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Anahtarı',
                hintText: 'AIza...',
              ),
            ),
          ],
        ),
        actions: [
          if (current != null && current.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('Anahtarı Sil',
                  style: TextStyle(color: AppTheme.statusExpired)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('İptal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Kaydet')),
        ],
      ),
    );

    if (action == 'save' && ctrl.text.trim().isNotEmpty) {
      await GeminiOcrService.instance.setApiKey(ctrl.text);
    } else if (action == 'clear') {
      await GeminiOcrService.instance.clearApiKey();
    }
    _load();
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
          IconButton(
            icon: Icon(
              _hasKey ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: _hasKey ? Colors.white : Colors.white70,
            ),
            tooltip: 'Online OCR Ayarı',
            onPressed: _openKeySettings,
          ),
        ],
      ),
      body: _loading
          ? const LoadingState()
          : _sessions.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _sessions.length + (_hasKey ? 0 : 1),
                    itemBuilder: (_, i) {
                      // Key yoksa en ustte uyari karti.
                      if (!_hasKey && i == 0) return _buildKeyBanner();
                      final s = _sessions[_hasKey ? i : i - 1];
                      return _sessionCard(s);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSession,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni Oturum'),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        if (!_hasKey)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildKeyBanner(),
          ),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const EmptyState(
            icon: Icons.receipt_long_rounded,
            iconColor: AppTheme.coral,
            title: 'Henüz oturum yok',
            subtitle:
                'Her fiyat değişim günü bir oturumdur: A4 listeleri tara, '
                'etiketleri değiştir (fotolu kanıt), eksikleri raporla.\n'
                'Başlamak için "Yeni Oturum"a dokunun.',
          ),
        ),
      ],
    );
  }

  Widget _buildKeyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(accentColor: AppTheme.statusWarning),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppTheme.statusWarning, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Online OCR kapalı — A4 okuma doğruluğu düşük olabilir. '
              'Gemini anahtarı ekleyin (ücretsiz).',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: _openKeySettings,
            child: const Text('Ayarla'),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(SessionSummary s) {
    final fmtDate = DateFormat('dd MMMM yyyy', 'tr');
    final fmtTime = DateFormat('HH:mm');
    final done = s.session.isCompleted;
    final color = done
        ? AppTheme.statusSafe
        : (s.pending == 0 && s.total > 0
            ? AppTheme.statusSafe
            : AppTheme.primary);

    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.rLg),
      onTap: () => _openSession(s),
      onLongPress: () => _deleteSession(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.card(accentColor: color),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      done
                          ? Icons.task_alt_rounded
                          : Icons.pending_actions_rounded,
                      color: color,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDate.format(s.session.createdAt),
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700)),
                      Text(
                        '${fmtTime.format(s.session.createdAt)}'
                        '${s.session.a4Count > 0 ? "  •  ${s.session.a4Count} A4" : ""}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(AppTheme.rPill),
                    border:
                        Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(
                    done ? 'Tamamlandı' : 'Devam ediyor',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ],
            ),
            if (s.total > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: s.progress,
                  minHeight: 6,
                  backgroundColor: AppTheme.surfaceAlt,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _miniStat('Toplam', s.total, AppTheme.textSecondary),
                  const SizedBox(width: 14),
                  _miniStat('Değişti', s.changed, AppTheme.statusSafe),
                  const SizedBox(width: 14),
                  _miniStat(
                      'Kalan',
                      s.pending,
                      s.pending > 0
                          ? AppTheme.statusWarning
                          : AppTheme.statusSafe),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Henüz A4 eklenmedi',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textTertiary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Row(
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11.5, color: AppTheme.textTertiary)),
      ],
    );
  }
}
