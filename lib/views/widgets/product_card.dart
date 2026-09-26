import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';

/// Modern product card used in inventory lists.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onDelete,
    this.onDispose,
    this.onSearch,
    this.partyCount = 1,
    this.locationLabel,
  });

  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onDispose;
  final VoidCallback? onSearch;
  final int partyCount;
  final String? locationLabel;

  @override
  Widget build(BuildContext context) {
    final status = product.status;
    final days = product.daysUntilExpiry;
    final dateStr = DateFormat('dd.MM.yyyy').format(product.expiryDate);

    Color statusColor;
    String statusLabel;

    if (days <= 0) {
      statusColor = AppTheme.danger;
      statusLabel = 'Süre doldu';
    } else if (days <= 7) {
      statusColor = AppTheme.warning;
      statusLabel = 'Yakında';
    } else {
      statusColor = AppTheme.success;
      statusLabel = 'Güvenli';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Dismissible(
        key: ValueKey('product_${product.id}'),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.endToStart) {
            onDispose?.call();
          } else {
            onTap?.call();
          }
          return false;
        },
        background: _swipeBackground(
          context,
          label: 'İmha',
          color: AppTheme.danger,
          alignment: Alignment.centerRight,
        ),
        secondaryBackground: _swipeBackground(
          context,
          label: 'Düzenle',
          color: AppTheme.primary,
          alignment: Alignment.centerLeft,
        ),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: statusColor.withOpacity(0.25), width: 1),
                        ),
                        child: Text(
                          statusLabel,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: statusColor,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metaChip(context, 'SKT', dateStr),
                      if (product.category != null) _metaChip(context, 'Kategori', product.category!),
                      _metaChip(context, 'Adet', '${product.quantity}'),
                      if (locationLabel != null && locationLabel!.isNotEmpty)
                        _metaChip(context, 'Konum', locationLabel!),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${days} gün kaldı',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (partyCount > 1)
                        Text(
                          '$partyCount parti',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          text: '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
          children: [
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeBackground(
    BuildContext context, {
    required String label,
    required Color color,
    required Alignment alignment,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
