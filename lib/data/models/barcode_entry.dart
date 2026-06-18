/// Barkod dizini modeli - Excel'den import edilen barkod/urun adi eslesmesi.
class BarcodeEntry {
  final int? id;
  final String barcode;
  final String productName;
  final String? stockCode; // urun stok kodu (4-6 hane, Excel'den)
  final DateTime importedAt;

  const BarcodeEntry({
    this.id,
    required this.barcode,
    required this.productName,
    this.stockCode,
    required this.importedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'barcode': barcode,
        'product_name': productName,
        'stock_code': stockCode,
        'imported_at': importedAt.millisecondsSinceEpoch,
      };

  factory BarcodeEntry.fromMap(Map<String, Object?> map) => BarcodeEntry(
        id: map['id'] as int?,
        barcode: map['barcode'] as String,
        productName: map['product_name'] as String,
        stockCode: map['stock_code'] as String?,
        importedAt:
            DateTime.fromMillisecondsSinceEpoch(map['imported_at'] as int),
      );
}
