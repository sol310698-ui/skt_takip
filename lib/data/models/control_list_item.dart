/// Yonetici KONTROL LISTESI satiri.
///
/// Excel veya fotograf (Gemini OCR) ile yuklenen urun listesindeki tek bir
/// satir. Yoneticinin attigi veriyi kullanici hizlica gozden gecirir; her
/// urunun barkodu otomatik internette aranir.
///
/// Sutunlar (kullanicinin paylastigi Excel basligina gore):
///   Sektor, Kategori, Stok Kodu, Barkod, Stok Adi, Stok, RBG (Gun),
///   Son Giris, Son Satis.
///   RBG = Rafta Bekleyen Gun.
class ControlListItem {
  final int? id;
  final String? sector; // Sektor (orn. ANPA - ATISTIRMALIK)
  final String? category; // Kategori (orn. CIPS, CIKOLATA)
  final String? stockCode; // Stok Kodu (orn. 56003565)
  final String? barcode; // Barkod (12-13 hane)
  final String? productName; // Stok Adi
  final int? stock; // Stok adedi
  final int? rbgDays; // RBG (Gun) — rafta bekleyen gun
  final String? lastEntry; // Son Giris (tarih metni; ham haliyle saklanir)
  final String? lastSale; // Son Satis (tarih metni)
  final bool checked; // kullanici bu satiri kontrol etti mi
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
    required this.importedAt,
  });

  ControlListItem copyWith({
    int? id,
    bool? checked,
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
        importedAt:
            DateTime.fromMillisecondsSinceEpoch(map['imported_at'] as int),
      );
}
