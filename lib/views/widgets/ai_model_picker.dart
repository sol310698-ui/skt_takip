import 'package:flutter/material.dart';

import '../../core/services/ai_model_prefs.dart';
import '../../core/theme/app_theme.dart';

/// Yapay zeka MODEL SECIMI dialogu.
/// Kullanicinin API anahtarindaki desteklenen tum modelleri tarar, listeler
/// ve secimi kalici saklar. "Otomatik" secenegi uygulamanin akilli yedek
/// listesini kullanir.
Future<void> showAiModelPicker(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _AiModelPickerDialog(),
  );
}

class _AiModelPickerDialog extends StatefulWidget {
  const _AiModelPickerDialog();
  @override
  State<_AiModelPickerDialog> createState() => _AiModelPickerDialogState();
}

class _AiModelPickerDialogState extends State<_AiModelPickerDialog> {
  final _prefs = AiModelPrefs.instance;

  @override
  void initState() {
    super.initState();
    // Ilk acilista liste bossa otomatik tara.
    if (_prefs.available.isEmpty && !_prefs.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefs.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _prefs,
      builder: (context, _) {
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Yapay Zeka Modeli')),
              IconButton(
                tooltip: 'Modelleri Tara',
                icon: _prefs.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
                onPressed: _prefs.loading ? null : _prefs.refresh,
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'API anahtarınızda desteklenen modeller tarandı. Seçtiğiniz '
                  'model tüm işlemlerde (OCR, sohbet, asistan) ilk sırada '
                  'kullanılır; hata olursa otomatik yedeklere düşülür.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                if (_prefs.error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.statusExpired.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_prefs.error!,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.statusExpired)),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // Otomatik secenegi.
                      _tile(
                        id: null,
                        title: 'Otomatik (önerilen)',
                        subtitle:
                            'Uygulama en iyi modeli seçer, gerekince yedeğe geçer',
                      ),
                      if (_prefs.available.isEmpty && !_prefs.loading)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'Model listesi boş. Yenile’ye dokunun.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textTertiary),
                            ),
                          ),
                        ),
                      ..._prefs.available.map((m) => _tile(
                            id: m.id,
                            title: m.displayName,
                            subtitle: _subtitle(m),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  String _subtitle(AiModelInfo m) {
    final parts = <String>[m.id];
    if (m.inputTokenLimit != null) {
      final k = (m.inputTokenLimit! / 1000).round();
      parts.add('$k K token');
    }
    return parts.join(' · ');
  }

  Widget _tile({
    required String? id,
    required String title,
    required String subtitle,
  }) {
    final selected = _prefs.selected == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AppTheme.primary.withOpacity(0.12)
            : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          onTap: () async {
            await _prefs.setSelected(id);
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
