/// Yonetici KONTROL LISTESI satiri.
///
/// Excel veya fotograf (Gemini OCR) ile yuklenen urun listesindeki tek bir
/// satir. SAYIM alanlari (el terminali tarzi):
///   countedQty — sayilan fiziksel adet (null = henuz sayilmadi)
///   countedAt  — son sayim zamani
class ControlListItem {
  final int? id;
  final String? sector;
  final String? category;
  final String? stockCode;
  final String? barcode;
  final String? productName;
  final int? stock;
  final int? rbgDays;
  final String? lastEntry;
  final String? lastSale;
  final bool checked;
  final int? countedQty;
  final DateTime? countedAt;
  final DateTime importedAt;

  const ControlListItem({
    this.id,
    this.sector,
    this.category,
    this.stockCode,
    this.barcode,
    this.productName,
    this.stock,
    this.rbgDays,
    this.lastEntry,
    this.lastSale,
    this.checked = false,
    this.countedQty,
    this.countedAt,
    required this.importedAt,
  });

  bool get isCounted => countedQty != null;

  ControlListItem copyWith({
    int? id,
    bool? checked,
    int? countedQty,
    DateTime? countedAt,
    bool clearCount = false,
  }) =>
      ControlListItem(
        id: id ?? this.id,
        sector: sector,
        category: category,
        stockCode: stockCode,
        barcode: barcode,
        productName: productName,
        stock: stock,
        rbgDays: rbgDays,
        lastEntry: lastEntry,
        lastSale: lastSale,
        checked: checked ?? this.checked,
        countedQty: clearCount ? null : (countedQty ?? this.countedQty),
        countedAt: clearCount ? null : (countedAt ?? this.countedAt),
        importedAt: importedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'sector': sector,
        'category': category,
        'stock_code': stockCode,
        'barcode': barcode,
        'product_name': productName,
        'stock': stock,
        'rbg_days': rbgDays,
        'last_entry': lastEntry,
        'last_sale': lastSale,
        'checked': checked ? 1 : 0,
        'counted_qty': countedQty,
        'counted_at': countedAt?.millisecondsSinceEpoch,
        'imported_at': importedAt.millisecondsSinceEpoch,
      };

  factory ControlListItem.fromMap(Map<String, Object?> map) => ControlListItem(
        id: map['id'] as int?,
        sector: map['sector'] as String?,
        category: map['category'] as String?,
        stockCode: map['stock_code'] as String?,
        barcode: map['barcode'] as String?,
        productName: map['product_name'] as String?,
        stock: map['stock'] as int?,
        rbgDays: map['rbg_days'] as int?,
        lastEntry: map['last_entry'] as String?,
        lastSale: map['last_sale'] as String?,
        checked: (map['checked'] as int? ?? 0) == 1,
        countedQty: map['counted_qty'] as int?,
        countedAt: map['counted_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['counted_at'] as int)
            : null,
        importedAt:
            DateTime.fromMillisecondsSinceEpoch(map['imported_at'] as int),
      );
}
