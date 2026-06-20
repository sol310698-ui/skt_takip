/// Etiket Basım ekranında bir barkodun listeye eklendiği ana ait
/// kalıcı geçmiş kaydı. "Geçmiş" sekmesinde gün gün gösterilir.
class LabelHistoryEntry {
  final int? id;
  final String barcode;
  final String productName;
  final String? stockCode;
  final String groupKey; // LabelGroup.name (kalinRon, inceRon, a4, ...)
  final String groupTitle; // gösterim adı (Kalın Reyon, A4, ...)
  final int quantity;
  final DateTime addedAt;

  LabelHistoryEntry({
    this.id,
    required this.barcode,
    required this.productName,
    this.stockCode,
    required this.groupKey,
    required this.groupTitle,
    required this.quantity,
    required this.addedAt,
  });

  Map<String, Object?> toMap() => {
        'barcode': barcode,
        'product_name': productName,
        'stock_code': stockCode,
        'group_key': groupKey,
        'group_title': groupTitle,
        'quantity': quantity,
        'added_at': addedAt.millisecondsSinceEpoch,
      };

  factory LabelHistoryEntry.fromMap(Map<String, Object?> m) => LabelHistoryEntry(
        id: m['id'] as int?,
        barcode: m['barcode'] as String,
        productName: m['product_name'] as String,
        stockCode: m['stock_code'] as String?,
        groupKey: m['group_key'] as String,
        groupTitle: m['group_title'] as String,
        quantity: m['quantity'] as int,
        addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
      );
}
