import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';

/// Imha / iade islemi icin kayan pencere.
class DisposalSheet extends ConsumerStatefulWidget {
  final Product product;
  const DisposalSheet({super.key, required this.product});

  @override
  ConsumerState<DisposalSheet> createState() => _DisposalSheetState();
}

class _DisposalSheetState extends ConsumerState<DisposalSheet> {
  DisposalStatus _selected = DisposalStatus.disposed;
  final TextEditingController _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(productListProvider.notifier).dispose_(
          widget.product.id!,
          _selected,
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
    await ref.read(disposalHistoryProvider.notifier).refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(widget.product.name,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('İşlem seçin',
                style: TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _OptionButton(
                    label: 'İmha',
                    icon: Icons.delete_forever_outlined,
                    color: const Color(0xFFD32F2F),
                    selected: _selected == DisposalStatus.disposed,
                    onTap: () =>
                        setState(() => _selected = DisposalStatus.disposed),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionButton(
                    label: 'Tedarikçiye İade',
                    icon: Icons.assignment_return_outlined,
                    color: const Color(0xFF1976D2),
                    selected: _selected == DisposalStatus.returned,
                    onTap: () =>
                        setState(() => _selected = DisposalStatus.returned),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Not (opsiyonel)',
                hintText: 'ör. Üretim hatası, ambalaj bozuk...',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : Text(_selected == DisposalStatus.disposed
                      ? 'İmha Kaydet'
                      : 'İade Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _OptionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withOpacity(0.15) : AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: color, width: 2)
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: selected ? color : AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
