import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/product.dart';

/// Urun karti - guclu hiyerarsi, belirgin SKT durumu.
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onDispose;
  final VoidCallback? onSearch;
  final int partyCount; // bu barkoddan kac aktif parti var

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onDelete,
    this.onDispose,
    this.onSearch,
    this.partyCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final status = product.status;
    final days = product.daysUntilExpiry;
    final dateStr = DateFormat('dd.MM.yyyy').format(product.expiryDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Dismissible(
        key: ValueKey('product_${product.id}'),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.endToStart) {
            // Sol kaydir -> imha onayi
            onDispose?.call();
          } else {
            // Sag kaydir -> duzenle
            onTap?.call();
          }
          return false; // Liste ogesi kalsin; aksiyon modal'da halleder.
        },
        background: _swipeBg(
          color: AppTheme.primary,
          icon: Icons.edit_rounded,
          label: 'Düzenle',
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 24),
        ),
        secondaryBackground: _swipeBg(
          color: AppTheme.statusExpired,
          icon: Icons.delete_sweep_rounded,
          label: 'İmha',
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              decoration: AppTheme.card(accentColor: status.color),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _dayCounter(status, days),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 12, color: AppTheme.textTertiary),
                          const SizedBox(width: 5),
                          Text(dateStr,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      if (product.quantity > 1 ||
                          product.category != null ||
                          partyCount > 1) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (partyCount > 1)
                              _chip('$partyCount parti',
                                  Icons.layers_rounded,
                                  color: AppTheme.accent),
                            if (product.quantity > 1)
                              _chip('${product.quantity} adet',
                                  Icons.inventory_2_rounded),
                            if (product.category != null)
                              _chip(product.category!,
                                  Icons.category_rounded),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Sag: menu
                _menu(),
              ],
            ),
          ),
        ),
      ),
      ), // Dismissible
    );
  }

  Widget _swipeBg({
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
    required EdgeInsets padding,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  /// Buyuk gun sayaci rozeti.
  Widget _dayCounter(ExpiryStatus status, int days) {
    final color = status.color;
    final String big;
    final String small;
    if (days < 0) {
      big = '${-days}';
      small = 'gün geçti';
    } else if (days == 0) {
      big = '!';
      small = 'bugün';
    } else {
      big = '$days';
      small = 'gün';
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.25), color.withOpacity(0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(big,
              style: TextStyle(
                  color: color,
                  fontSize: days < 0 || days > 99 ? 20 : 24,
                  fontWeight: FontWeight.w900,
                  height: 1)),
          Text(small,
              style: TextStyle(
                  color: color.withOpacity(0.9),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, {Color? color}) {
    final c = color ?? AppTheme.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color != null
            ? color.withOpacity(0.12)
            : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: color != null
            ? Border.all(color: color.withOpacity(0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: c,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textTertiary),
      color: AppTheme.surfaceHigh,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_rounded, size: 18),
            SizedBox(width: 10),
            Text('Düzenle'),
          ]),
        ),
        if (product.barcode != null)
          const PopupMenuItem(
            value: 'search',
            child: Row(children: [
              Icon(Icons.search_rounded, size: 18, color: AppTheme.accent),
              SizedBox(width: 10),
              Text("Google'da Ara",
                  style: TextStyle(color: AppTheme.accent)),
            ]),
          ),
        const PopupMenuItem(
          value: 'dispose',
          child: Row(children: [
            Icon(Icons.delete_sweep_rounded,
                size: 18, color: AppTheme.statusWarning),
            SizedBox(width: 10),
            Text('İmha / İade',
                style: TextStyle(color: AppTheme.statusWarning)),
          ]),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded,
                size: 18, color: AppTheme.statusExpired),
            SizedBox(width: 10),
            Text('Sil', style: TextStyle(color: AppTheme.statusExpired)),
          ]),
        ),
      ],
      onSelected: (value) {
        if (value == 'edit') onTap?.call();
        if (value == 'dispose') onDispose?.call();
        if (value == 'delete') onDelete?.call();
        if (value == 'search') onSearch?.call();
      },
    );
  }
}
