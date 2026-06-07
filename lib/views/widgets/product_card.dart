import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';
import 'status_badge.dart';

/// Tek bir urunu glass-style kart olarak gosterir.
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onDispose;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onDelete,
    this.onDispose,
  });

  @override
  Widget build(BuildContext context) {
    final status = product.status;
    final days = product.daysUntilExpiry;
    final dateStr = DateFormat('dd.MM.yyyy').format(product.expiryDate);

    final daysLabel = days < 0
        ? '${-days} gün önce doldu'
        : days == 0
            ? 'Bugün doluyor'
            : '$days gün kaldı';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: AppTheme.glassCard(accent: status.color),
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.event,
                              size: 13,
                              color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '$dateStr  ·  $daysLabel',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (product.quantity > 1 || product.category != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (product.quantity > 1)
                              'Adet: ${product.quantity}',
                            if (product.category != null) product.category!,
                          ].join('  ·  '),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 8),
                      StatusBadge(status: status),
                    ],
                  ),
                ),
                // Islem menusu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: AppTheme.textSecondary),
                  color: AppTheme.surfaceAlt,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Düzenle'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'dispose',
                      child: Row(children: [
                        Icon(Icons.delete_sweep_outlined,
                            size: 18, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('İmha / İade',
                            style: TextStyle(color: Colors.orange)),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Sil', style: TextStyle(color: Colors.red)),
                      ]),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') onTap?.call();
                    if (value == 'dispose') onDispose?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
