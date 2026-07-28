import 'product.dart';

class FixedListing {
  final int id;
  final Product item;
  final double price;
  final double? originalPrice;
  final double? discountPercentage;
  final double depositPercentage;
  final double depositAmount;
  final bool isActive;

  FixedListing({
    required this.id,
    required this.item,
    required this.price,
    this.originalPrice,
    this.discountPercentage,
    required this.depositPercentage,
    required this.depositAmount,
    required this.isActive,
  });

  factory FixedListing.fromJson(Map<String, dynamic> json) {
    final itemJson = json['item'] as Map<String, dynamic>;
    return FixedListing(
      id: json['id'] as int,
      item: Product.fromJson(itemJson),
      price: double.parse(json['price'] as String),
      originalPrice: double.tryParse(json['original_price']?.toString() ?? ''),
      discountPercentage:
          double.tryParse(json['discount_percentage']?.toString() ?? ''),
      depositPercentage: double.parse(json['deposit_percentage'] as String),
      depositAmount: double.parse(json['deposit_amount'] as String),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}