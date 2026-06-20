/// Baska bir ekrandan (ornegin Fiyat Degisim) "Etiket Basim'a da gonder"
/// secilince olusturulan bekleyen kayit. Etiket Basim ekrani acildiginda
/// bu kuyruk okunur, kendi listesine eklenir ve kuyruktan silinir.
class LabelPendingItem {
  final int? id;
  final String barcode;
  final String productName;
  final String? stockCode;
  final String groupKey; // LabelGroup.name
  final int quantity;
  final String source; // hangi ekrandan geldi (orn. 'price_change')
  final DateTime addedAt;

  LabelPendingItem({
    this.id,
    required this.barcode,
    required this.productName,
    this.stockCode,
    required this.groupKey,
    this.quantity = 1,
    required this.source,
    required this.addedAt,
  });

  Map<String, Object?> toMap() => {
        'barcode': barcode,
        'product_name': productName,
        'stock_code': stockCode,
        'group_key': groupKey,
        'quantity': quantity,
        'source': source,
        'added_at': addedAt.millisecondsSinceEpoch,
      };

  factory LabelPendingItem.fromMap(Map<String, Object?> m) => LabelPendingItem(
        id: m['id'] as int?,
        barcode: m['barcode'] as String,
        productName: m['product_name'] as String,
        stockCode: m['stock_code'] as String?,
        groupKey: m['group_key'] as String,
        quantity: m['quantity'] as int,
        source: m['source'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
      );
}
