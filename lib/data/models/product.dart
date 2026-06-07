import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';

/// Ürün veri modeli.
class Product {
  final int? id;
  final String name;
  final String? barcode;
  final DateTime expiryDate;
  final int quantity;
  final String? category;
  final DateTime createdAt;

  const Product({
    this.id,
    required this.name,
    this.barcode,
    required this.expiryDate,
    this.quantity = 1,
    this.category,
    required this.createdAt,
  });

  /// SKT durumunu döner (hesaplanmış alan).
  ExpiryStatus get status => DateUtils.statusFor(expiryDate);

  /// SKT'ye kalan gün.
  int get daysUntilExpiry => DateUtils.daysUntil(expiryDate);

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    DateTime? expiryDate,
    int? quantity,
    String? category,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      expiryDate: expiryDate ?? this.expiryDate,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
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
    };
  }

  factory Product.fromMap(Map<String, Object?> map) {
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
    );
  }
}
