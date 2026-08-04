/// SAYIM kalemi: bir barkod + sayilan adet. Bir sayim OTURUMUNA baglidir
/// (sessionId). Urun adi (varsa) barkod dizininden bulunur; yoksa null.
class CountItem {
  final int? id;
  final int sessionId;
  final String barcode;
  final String? productName;
  final int qty;
  final DateTime countedAt;

  const CountItem({
    this.id,
    this.sessionId = 0,
    required this.barcode,
    this.productName,
    required this.qty,
    required this.countedAt,
  });

  CountItem copyWith({int? id, int? sessionId, String? productName, int? qty}) =>
      CountItem(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        barcode: barcode,
        productName: productName ?? this.productName,
        qty: qty ?? this.qty,
        countedAt: countedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'session_id': sessionId,
        'barcode': barcode,
        'product_name': productName,
        'qty': qty,
        'counted_at': countedAt.millisecondsSinceEpoch,
      };

  factory CountItem.fromMap(Map<String, Object?> map) => CountItem(
        id: map['id'] as int?,
        sessionId: (map['session_id'] as int?) ?? 0,
        barcode: map['barcode'] as String,
        productName: map['product_name'] as String?,
        qty: map['qty'] as int,
        countedAt:
            DateTime.fromMillisecondsSinceEpoch(map['counted_at'] as int),
      );
}

/// SAYIM OTURUMU: bir sayim seansi (isim + acilis + kapanis). Kalem sayisi
/// ve toplam adet, listelenirken hesaplanip doldurulur.
class CountSession {
  final int? id;
  final String name;
  final String? note;
  final DateTime createdAt;
  final DateTime? closedAt;

  // Listeleme sirasinda doldurulan ozet (agg ile).
  final int itemCount;
  final int totalQty;

  const CountSession({
    this.id,
    required this.name,
    this.note,
    required this.createdAt,
    this.closedAt,
    this.itemCount = 0,
    this.totalQty = 0,
  });

  bool get isClosed => closedAt != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'closed_at': closedAt?.millisecondsSinceEpoch,
      };

  factory CountSession.fromMap(Map<String, Object?> map,
          {int itemCount = 0, int totalQty = 0}) =>
      CountSession(
        id: map['id'] as int?,
        name: map['name'] as String,
        note: map['note'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        closedAt: map['closed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['closed_at'] as int),
        itemCount: itemCount,
        totalQty: totalQty,
      );
}
