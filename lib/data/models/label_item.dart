/// Etiket basim sayfasinda yer alan tek bir urun satiri.
/// Barkod taranarak, dizinden secilerek veya kisa kod ile eklenebilir.
class LabelItem {
  final String barcode;
  final String productName;
  final String? stockCode; // kisa kod (varsa)
  int quantity; // ayni etiketten kac adet

  LabelItem({
    required this.barcode,
    required this.productName,
    this.stockCode,
    this.quantity = 1,
  });

  LabelItem copyWith({
    String? barcode,
    String? productName,
    String? stockCode,
    int? quantity,
  }) =>
      LabelItem(
        barcode: barcode ?? this.barcode,
        productName: productName ?? this.productName,
        stockCode: stockCode ?? this.stockCode,
        quantity: quantity ?? this.quantity,
      );
}
