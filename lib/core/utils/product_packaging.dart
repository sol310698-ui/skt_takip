/// ════════════════════════════════════════════════════════════════════
///  ÜRÜN PAKETLEME BİLGİSİ — ürün adının sonunda genelde şu kalıp olur:
///
///     ... ÜRÜN ADI ... *12 (PLT-72)
///                       │      └── bir PALETİN alacağı MAKSİMUM KOLİ sayısı
///                       └── bir KOLİ içindeki ürün adedi
///
///  Bu dosya bu kalıbı ürün adından ayıklar; depo ekranlarında "1 koli
///  = 12 adet", "palet dolar = 72 koli" gibi detayları göstermek ve
///  koli bazında miktar girişi yapabilmek için kullanılır.
/// ════════════════════════════════════════════════════════════════════
class ProductPackagingInfo {
  final int? piecesPerCase; // *12 -> bir koli 12 adet
  final int? palletCaseCapacity; // (PLT-72) -> palet 72 koli alir
  const ProductPackagingInfo({this.piecesPerCase, this.palletCaseCapacity});

  bool get hasAny => piecesPerCase != null || palletCaseCapacity != null;
}

final _piecesRe = RegExp(r'\*\s*(\d{1,4})\b');
final _palletRe = RegExp(r'PLT[\s\-:]*?(\d{1,4})', caseSensitive: false);

/// Ürün adından paketleme bilgisini ayıklar. Bulunamayan alanlar null
/// döner - hicbir sey bulunamazsa hasAny=false olur.
ProductPackagingInfo parseProductPackaging(String? name) {
  if (name == null || name.isEmpty) return const ProductPackagingInfo();
  // Birden fazla "*NN" gecebilir (urun adinda baska yildiz olabilir) -
  // SONUNCUSUNU al, kalip genelde adin en sonunda olur.
  final piecesMatches = _piecesRe.allMatches(name).toList();
  final piecesPerCase = piecesMatches.isEmpty
      ? null
      : int.tryParse(piecesMatches.last.group(1)!);
  final palletMatch = _palletRe.firstMatch(name);
  final palletCap =
      palletMatch != null ? int.tryParse(palletMatch.group(1)!) : null;
  return ProductPackagingInfo(
    piecesPerCase: piecesPerCase,
    palletCaseCapacity: palletCap,
  );
}
