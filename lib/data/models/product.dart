import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';

/// Urun imha/iade durumu.
enum DisposalStatus {
  active,    // Aktif, rafta
  disposed,  // Imha edildi
  returned;  // Tedarikçiye iade

  String get label {
    switch (this) {
      case DisposalStatus.active:   return 'Aktif';
      case DisposalStatus.disposed: return 'İmha';
      case DisposalStatus.returned: return 'İade';
    }
  }
}

/// Ürün veri modeli.
class Product {
  final int? id;
  final String name;
  final String? barcode;
  final DateTime expiryDate;
  final int quantity;
  final String? category;
  final DateTime createdAt;
  final DisposalStatus disposalStatus;
  final DateTime? disposalDate;
  final String? disposalNote;

  const Product({
    this.id,
    required this.name,
    this.barcode,
    required this.expiryDate,
    this.quantity = 1,
    this.category,
    required this.createdAt,
    this.disposalStatus = DisposalStatus.active,
    this.disposalDate,
    this.disposalNote,
  });

  ExpiryStatus get status => DateUtils.statusFor(expiryDate);
  int get daysUntilExpiry => DateUtils.daysUntil(expiryDate);
  bool get isActive => disposalStatus == DisposalStatus.active;

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    DateTime? expiryDate,
    int? quantity,
    String? category,
    DateTime? createdAt,
    DisposalStatus? disposalStatus,
    DateTime? disposalDate,
    String? disposalNote,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      expiryDate: expiryDate ?? this.expiryDate,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      disposalStatus: disposalStatus ?? this.disposalStatus,
      disposalDate: disposalDate ?? this.disposalDate,
      disposalNote: disposalNote ?? this.disposalNote,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'expiry_date': expiryDate.millisecondsSinceEpoch,
      'quantity': quantity,
      'category': category,
      'created_at': createdAt.millisecondsSinceEpoch,
      'disposal_status': disposalStatus.name,
      'disposal_date': disposalDate?.millisecondsSinceEpoch,
      'disposal_note': disposalNote,
    };
  }

  factory Product.fromMap(Map<String, Object?> map) {
    DisposalStatus ds = DisposalStatus.active;
    final dsStr = map['disposal_status'] as String?;
    if (dsStr != null) {
      ds = DisposalStatus.values.firstWhere(
        (e) => e.name == dsStr,
        orElse: () => DisposalStatus.active,
      );
    }
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      barcode: map['barcode'] as String?,
      expiryDate:
          DateTime.fromMillisecondsSinceEpoch(map['expiry_date'] as int),
      quantity: (map['quantity'] as int?) ?? 1,
      category: map['category'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      disposalStatus: ds,
      disposalDate: map['disposal_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['disposal_date'] as int)
          : null,
      disposalNote: map['disposal_note'] as String?,
    );
  }
}
