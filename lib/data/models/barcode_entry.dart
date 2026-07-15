/// Barkod dizini kayit kaynagi. Veri onceligini belirler:
/// screen > Excel > manual > scan > off (internet).
///
/// 'screen' = sirket uygulamasinin URUN DETAY ekranindan, erisilebilirlik
/// servisiyle DOGRUDAN okunan veri. Bu, sirketin kendi sistemindeki guncel
/// gercegi yansittigi icin EN GUVENILIR kaynak kabul edilir ve Excel dahil
/// her seyin uzerine yazar (kullanici bu yonde karar verdi).
enum BarcodeSource { screen, excel, manual, scan, off, unknown }

extension BarcodeSourceX on BarcodeSource {
  String get dbValue {
    switch (this) {
      case BarcodeSource.screen:
        return 'screen';
      case BarcodeSource.excel:
        return 'excel';
      case BarcodeSource.manual:
        return 'manual';
      case BarcodeSource.scan:
        return 'scan';
      case BarcodeSource.off:
        return 'off';
      case BarcodeSource.unknown:
        return 'unknown';
    }
  }

  /// Onceligi sayisal olarak dondurur (buyuk = daha guvenilir).
  /// screen (sirket ekrani) en yuksek; off (internet) en dusuk.
  int get priority {
    switch (this) {
      case BarcodeSource.screen:
        return 5;
      case BarcodeSource.excel:
        return 4;
      case BarcodeSource.manual:
        return 3;
      case BarcodeSource.scan:
        return 2;
      case BarcodeSource.off:
        return 1;
      case BarcodeSource.unknown:
        return 0;
    }
  }

  static BarcodeSource fromDb(String? v) {
    switch (v) {
      case 'screen':
        return BarcodeSource.screen;
      case 'excel':
        return BarcodeSource.excel;
      case 'manual':
        return BarcodeSource.manual;
      case 'scan':
        return BarcodeSource.scan;
      case 'off':
        return BarcodeSource.off;
      default:
        return BarcodeSource.unknown;
    }
  }
}

/// Barkod dizini modeli - Excel'den import edilen barkod/urun adi eslesmesi
/// (ayrica internet/manuel/tarama kaynakli kayitlar).
class BarcodeEntry {
  final int? id;
  final String barcode;
  final String productName;
  final String? stockCode; // urun stok kodu (4-6 hane, Excel'den)
  final DateTime importedAt;
  final BarcodeSource source; // kaydin kaynagi (oncelik icin)
  final String? localImagePath; // internet fotografi yoksa gosterilecek yerel foto

  const BarcodeEntry({
    this.id,
    required this.barcode,
    required this.productName,
    this.stockCode,
    required this.importedAt,
    this.source = BarcodeSource.unknown,
    this.localImagePath,
  });

  BarcodeEntry copyWith({
    int? id,
    String? barcode,
    String? productName,
    String? stockCode,
    DateTime? importedAt,
    BarcodeSource? source,
    String? localImagePath,
  }) =>
      BarcodeEntry(
        id: id ?? this.id,
        barcode: barcode ?? this.barcode,
        productName: productName ?? this.productName,
        stockCode: stockCode ?? this.stockCode,
        importedAt: importedAt ?? this.importedAt,
        source: source ?? this.source,
        localImagePath: localImagePath ?? this.localImagePath,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'barcode': barcode,
        'product_name': productName,
        'stock_code': stockCode,
        'imported_at': importedAt.millisecondsSinceEpoch,
        'source': source.dbValue,
        'local_image_path': localImagePath,
      };

  factory BarcodeEntry.fromMap(Map<String, Object?> map) => BarcodeEntry(
        id: map['id'] as int?,
        barcode: map['barcode'] as String,
        productName: map['product_name'] as String,
        stockCode: map['stock_code'] as String?,
        importedAt:
            DateTime.fromMillisecondsSinceEpoch(map['imported_at'] as int),
        source: BarcodeSourceX.fromDb(map['source'] as String?),
        localImagePath: map['local_image_path'] as String?,
      );
}
