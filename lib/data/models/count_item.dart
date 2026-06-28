/// Bagimsiz SAYIM kaydi: bir barkod + sayilan adet.
///
/// Sayim mantigi cok basit: barkod okunur, adet girilir, kaydedilir.
/// Urun adi (varsa) barkod dizininden bulunur; yoksa null.
class CountItem {
  final int? id;
  final String barcode;
  final String? productName;
  final int qty;
  final DateTime countedAt;

  const CountItem({
    this.id,
    required this.barcode,
    this.productName,
    required this.qty,
    required this.countedAt,
  });

  CountItem copyWith({int? id, String? productName, int? qty}) => CountItem(
        id: id ?? this.id,
        barcode: barcode,
        productName: productName ?? this.productName,
        qty: qty ?? this.qty,
        countedAt: countedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'barcode': barcode,
        'product_name': productName,
        'qty': qty,
        'counted_at': countedAt.millisecondsSinceEpoch,
      };

  factory CountItem.fromMap(Map<String, Object?> map) => CountItem(
        id: map['id'] as int?,
        barcode: map['barcode'] as String,
        productName: map['product_name'] as String?,
        qty: map['qty'] as int,
        countedAt:
            DateTime.fromMillisecondsSinceEpoch(map['counted_at'] as int),
      );
}
