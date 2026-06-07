import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/google_search_button.dart';

/// Reyon kontrolde sorun cikinca acilan kayan pencere.
enum ShelfAlertType { mismatch, priceDiff }

class ShelfAlertSheet extends StatelessWidget {
  final ShelfAlertType type;
  final String productBarcode;
  final String labelBarcode;
  final double? oldPrice;
  final double? newPrice;
  final DateTime? priceUpdateDate;
  final DateTime? printDate;

  const ShelfAlertSheet({
    super.key,
    required this.type,
    required this.productBarcode,
    required this.labelBarcode,
    this.oldPrice,
    this.newPrice,
    this.priceUpdateDate,
    this.printDate,
  });

  @override
  Widget build(BuildContext context) {
    final isMismatch = type == ShelfAlertType.mismatch;
    final color =
        isMismatch ? const Color(0xFFD32F2F) : const Color(0xFFF57C00);
    final searchBarcode = isMismatch ? labelBarcode : labelBarcode;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Baslik
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                    isMismatch
                        ? Icons.error_outline
                        : Icons.price_change_outlined,
                    color: color,
                    size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isMismatch ? 'Barkod Uyuşmuyor!' : 'Fiyat Farkı!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (isMismatch) ..._buildMismatch() else ..._buildPriceDiff(),

          const SizedBox(height: 20),
          // Barkod + Google arama
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code,
                    size: 20, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(searchBarcode,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 15)),
                ),
                GoogleSearchButton(query: searchBarcode, compact: true),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Devam Et (Sonraki Etiket)'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMismatch() {
    return [
      _row('Ürün Barkodu', productBarcode, AppTheme.textPrimary),
      const SizedBox(height: 8),
      _row('Etiket Barkodu', labelBarcode, const Color(0xFFD32F2F)),
      const SizedBox(height: 12),
      const Text(
        'Bu etiket okuttuğunuz ürüne ait değil. Yanlış etiket olabilir.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    ];
  }

  List<Widget> _buildPriceDiff() {
    return [
      // Buyuk fiyat gosterimi
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const Text('Önceki',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '${oldPrice?.toStringAsFixed(2) ?? "-"} ₺',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      decoration: TextDecoration.lineThrough),
                ),
              ],
            ),
            const Icon(Icons.arrow_forward,
                color: Color(0xFFF57C00), size: 28),
            Column(
              children: [
                const Text('Yeni',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '${newPrice?.toStringAsFixed(2) ?? "-"} ₺',
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFF57C00)),
                ),
              ],
            ),
          ],
        ),
      ),
      if (priceUpdateDate != null || printDate != null) ...[
        const SizedBox(height: 12),
        if (priceUpdateDate != null)
          _row('Fiyat Güncelleme',
              DateFormat('dd.MM.yyyy').format(priceUpdateDate!),
              AppTheme.textPrimary),
        if (printDate != null) ...[
          const SizedBox(height: 6),
          _row('Basım Tarihi',
              DateFormat('dd.MM.yyyy HH:mm').format(printDate!),
              AppTheme.textPrimary),
        ],
      ],
    ];
  }

  Widget _row(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: AppTheme.textSecondary)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: valueColor)),
      ],
    );
  }
}
