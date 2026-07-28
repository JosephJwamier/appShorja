class StoreCoupon {
  final int id;
  final int store;
  final String storeName;
  final String code;
  final double amount;
  final double minOrderAmount;
  final String description;
  final bool isActive;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final bool isCollected;

  StoreCoupon({
    required this.id,
    required this.store,
    this.storeName = '',
    required this.code,
    required this.amount,
    required this.minOrderAmount,
    required this.description,
    required this.isActive,
    this.expiresAt,
    required this.createdAt,
    required this.isCollected,
  });

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory StoreCoupon.fromJson(Map<String, dynamic> json) {
    return StoreCoupon(
      id: json['id'] as int,
      store: json['store'] as int,
      storeName: json['store_name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      amount: _toDouble(json['amount']),
      minOrderAmount: _toDouble(json['min_order_amount']),
      description: json['description'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      isCollected: json['is_collected'] as bool? ?? false,
    );
  }
}
