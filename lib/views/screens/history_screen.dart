import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';
import '../../viewmodels/providers.dart';
import '../widgets/ui_kit.dart';

/// Imha ve iade gecmisi ekrani (son 90 gun).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(disposalHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('İmha & İade Geçmişi')),
      body: historyAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) =>
            const ErrorStateView(message: 'Geçmiş yüklenemedi'),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'Geçmiş kaydı yok',
              subtitle: 'Son 90 günlük imha ve iade kayıtları burada görünür',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, i) => _HistoryCard(product: list[i]),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Product product;
  const _HistoryCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final isDisposed = product.disposalStatus == DisposalStatus.disposed;
    final color =
        isDisposed ? const Color(0xFFD32F2F) : const Color(0xFF1976D2);
    final icon = isDisposed
        ? Icons.delete_forever_outlined
        : Icons.assignment_return_outlined;

    final disposalDateStr = product.disposalDate != null
        ? DateFormat('dd.MM.yyyy').format(product.disposalDate!)
        : '-';
    final expiryStr = DateFormat('dd.MM.yyyy').format(product.expiryDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('SKT: $expiryStr  ·  ${product.disposalStatus.label}: $disposalDateStr',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  if (product.disposalNote != null) ...[
                    const SizedBox(height: 2),
                    Text(product.disposalNote!,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
