import 'store_coupon.dart';

class CouponCollection {
  final int id;
  final StoreCoupon coupon;
  final DateTime collectedAt;
  final bool isUsed;
  final bool isExpired;

  CouponCollection({
    required this.id,
    required this.coupon,
    required this.collectedAt,
    required this.isUsed,
    required this.isExpired,
  });

  bool get isUsable => !isUsed && !isExpired && coupon.isActive;

  factory CouponCollection.fromJson(Map<String, dynamic> json) {
    return CouponCollection(
      id: json['id'] as int,
      coupon: StoreCoupon.fromJson(json['coupon'] as Map<String, dynamic>),
      collectedAt: DateTime.parse(json['collected_at'] as String),
      isUsed: json['is_used'] as bool? ?? false,
      isExpired: json['is_expired'] as bool? ?? false,
    );
  }
}
