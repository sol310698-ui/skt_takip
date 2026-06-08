import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/google_search_button.dart';

/// Reyon kontrol sonuc tipleri.
enum ShelfResultType {
  product,    // urun onayi
  matchFirst, // ilk etiket, referans fiyat
  matchSame,  // eslesti, fiyat ayni
  priceDiff,  // eslesti, fiyat farkli
  mismatch,   // barkod uyusmuyor
}

/// Reyon kontrolde her tarama sonrasi acilan kayan pencere.
class ShelfResultSheet extends StatelessWidget {
  final ShelfResultType type;
  final String barcode;          // okunan barkod (urun veya etiket)
  final String? productBarcode;  // referans urun barkodu (etiket asamasinda)
  final String? productName;     // dizinden bulunan ad
  final double? price;
  final double? oldPrice;
  final DateTime? priceUpdateDate;
  final DateTime? printDate;

  const ShelfResultSheet({
    super.key,
    required this.type,
    required this.barcode,
    this.productBarcode,
    this.productName,
    this.price,
    this.oldPrice,
    this.priceUpdateDate,
    this.printDate,
  });

  _Style get _style {
    switch (type) {
      case ShelfResultType.product:
        return _Style(AppTheme.primary, Icons.inventory_2_rounded,
            'Ürün Okundu');
      case ShelfResultType.matchFirst:
        return _Style(AppTheme.statusSafe, Icons.check_circle_rounded,
            'Eşleşti');
      case ShelfResultType.matchSame:
        return _Style(AppTheme.statusSafe, Icons.check_circle_rounded,
            'Eşleşti — Fiyat Aynı');
      case ShelfResultType.priceDiff:
        return _Style(AppTheme.statusCritical, Icons.price_change_rounded,
            'Fiyat Farkı!');
      case ShelfResultType.mismatch:
        return _Style(AppTheme.statusExpired, Icons.error_rounded,
            'Barkod Uyuşmuyor!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style;
    final isProduct = type == ShelfResultType.product;

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
              width: 44, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Baslik
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: s.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(s.icon, color: s.color, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: s.color)),
                    if (productName != null)
                      Text(productName!,
                          style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Govde
          if (type == ShelfResultType.mismatch)
            _mismatchBody()
          else if (type == ShelfResultType.priceDiff)
            _priceDiffBody()
          else if (price != null &&
              (type == ShelfResultType.matchFirst ||
                  type == ShelfResultType.matchSame))
            _priceBody()
          else if (isProduct)
            _productBody(),

          const SizedBox(height: 18),
          _barcodeBar(),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: s.color),
            child: Text(
              isProduct ? 'Etiketleri Taramaya Başla' : 'Devam Et',
            ),
          ),
        ],
      ),
    );
  }

  Widget _productBody() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: AppTheme.textSecondary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Şimdi bu ürünün raf etiketlerini arka arkaya okutun.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceBody() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppTheme.statusSafe.withOpacity(0.12),
          AppTheme.statusSafe.withOpacity(0.04),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.statusSafe.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text('Etiket Fiyatı',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text('${price!.toStringAsFixed(2)} ₺',
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.statusSafe,
                  height: 1)),
          if (type == ShelfResultType.matchFirst) ...[
            const SizedBox(height: 6),
            const Text('Referans olarak kaydedildi',
                style: TextStyle(
                    color: AppTheme.textTertiary, fontSize: 12)),
          ],
          _dateRow(),
        ],
      ),
    );
  }

  Widget _priceDiffBody() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.statusCritical.withOpacity(0.14),
              AppTheme.statusCritical.withOpacity(0.04),
            ]),
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: AppTheme.statusCritical.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(
                children: [
                  const Text('Önceki',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${oldPrice?.toStringAsFixed(2) ?? "-"} ₺',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textTertiary,
                          decoration: TextDecoration.lineThrough)),
                ],
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppTheme.statusCritical, size: 30),
              Column(
                children: [
                  const Text('Yeni',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${price?.toStringAsFixed(2) ?? "-"} ₺',
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.statusCritical)),
                ],
              ),
            ],
          ),
        ),
        _dateRow(),
      ],
    );
  }

  Widget _mismatchBody() {
    return Column(
      children: [
        _infoRow('Okuttuğunuz Ürün', productBarcode ?? '-',
            AppTheme.textPrimary),
        const SizedBox(height: 8),
        _infoRow('Etiketteki Barkod', barcode, AppTheme.statusExpired),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.statusExpired.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Bu etiket okuttuğunuz ürüne ait değil. Yanlış raf etiketi olabilir.',
            style: TextStyle(
                color: AppTheme.statusExpired, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _dateRow() {
    final items = <Widget>[];
    if (priceUpdateDate != null) {
      items.add(_dateChip(Icons.update_rounded, 'Fiyat',
          DateFormat('dd.MM.yyyy').format(priceUpdateDate!)));
    }
    if (printDate != null) {
      items.add(_dateChip(Icons.print_rounded, 'Basım',
          DateFormat('dd.MM.yy HH:mm').format(printDate!)));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            items[i],
          ],
        ],
      ),
    );
  }

  Widget _dateChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textTertiary),
          const SizedBox(width: 5),
          Text('$label: $value',
              style: const TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Flexible(
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: valueColor),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _barcodeBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code_rounded,
              size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(barcode,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 14.5)),
          ),
          GoogleSearchButton(query: barcode, compact: true),
        ],
      ),
    );
  }
}

class _Style {
  final Color color;
  final IconData icon;
  final String title;
  _Style(this.color, this.icon, this.title);
}
