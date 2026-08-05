import '../utils/formatters.dart';
import 'user.dart';

class Product {
  final int id;
  final String title;
  final String? nameAr;
  final String description;
  final String condition;
  final String status;
  final int quantity;
  final String packageSize;
  final int warrantyDays;
  final User owner;
  final List<String> imageUrls;
  final List<int> imageIds;
  final int? categoryId;
  final double? price;
  final double? originalPrice;
  final double? discountPercentage;
  final bool isDailyDeal;
  final double? rating;
  final int? soldCount;
  final int? totalReviews;
  final int? representativeAssignmentId;
  final String? representativeCommissionPercentage;

  Product({
    required this.id,
    required this.title,
    this.nameAr,
    required this.description,
    required this.condition,
    required this.status,
    required this.quantity,
    this.packageSize = 'medium',
    this.warrantyDays = 7,
    required this.owner,
    required this.imageUrls,
    this.imageIds = const [],
    this.categoryId,
    this.price,
    this.originalPrice,
    this.discountPercentage,
    this.isDailyDeal = false,
    this.rating,
    this.soldCount,
    this.totalReviews,
    this.representativeAssignmentId,
    this.representativeCommissionPercentage,
  });

  /// True when this listing reached the store through a representative
  /// (sales agent) assignment rather than the store owner's own item —
  /// reservations must route through [representativeAssignmentId] for the
  /// commission to be attributed.
  bool get isViaRepresentative => representativeAssignmentId != null;

  bool get isUsed => condition != 'new';

  String? get firstImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  factory Product.fromJson(Map<String, dynamic> json) {
    final imagesList = (json['images'] as List<dynamic>?) ?? [];
    final imageUrls = <String>[];
    final imageIds = <int>[];
    for (final img in imagesList) {
      final map = img as Map<String, dynamic>;
      final url = fixMediaUrl(map['image'] as String?);
      if (url.isEmpty) continue;
      imageUrls.add(url);
      final id = map['id'];
      if (id is int) imageIds.add(id);
    }
    final rawCategory = json['category'];
    final categoryId = rawCategory is Map<String, dynamic>
        ? rawCategory['id'] as int?
        : rawCategory is int
            ? rawCategory
            : null;
    final representativeInfo =
        json['representative_info'] as Map<String, dynamic>?;
    return Product(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      nameAr: json['name_ar'] as String?,
      description: json['description'] as String? ?? '',
      condition: json['condition'] as String? ?? 'used',
      status: json['status'] as String? ?? 'active',
      quantity: json['quantity'] as int? ?? 0,
      packageSize: json['package_size'] as String? ?? 'medium',
      warrantyDays: json['warranty_days'] as int? ?? 7,
      owner: User.fromJson(json['owner'] as Map<String, dynamic>? ?? {}),
      imageUrls: imageUrls,
      imageIds: imageIds,
      categoryId: categoryId,
      price: (json['price'] as num?)?.toDouble(),
      originalPrice: double.tryParse(json['original_price']?.toString() ?? ''),
      discountPercentage:
          double.tryParse(json['discount_percentage']?.toString() ?? ''),
      isDailyDeal: json['is_daily_deal'] as bool? ?? false,
      rating: double.tryParse(json['rating']?.toString() ?? ''),
      soldCount: json['sold_count'] as int?,
      totalReviews: json['total_reviews'] as int?,
      representativeAssignmentId:
          representativeInfo?['representative_assignment_id'] as int?,
      representativeCommissionPercentage:
          representativeInfo?['commission_percentage'] as String?,
    );
  }
}