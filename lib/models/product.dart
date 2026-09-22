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
  final bool isFavorited;

  /// The axes a buyer picks along (colour, size…). Empty for a plain item.
  final List<ProductOption> options;

  /// Every sellable combination. Always at least one — a plain item carries a
  /// single variant with empty [ProductVariant.attributes] holding its stock.
  final List<ProductVariant> variants;

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
    this.isFavorited = false,
    this.options = const [],
    this.variants = const [],
  });

  bool get hasOptions => options.isNotEmpty;

  /// 'أحمر / L' in the seller's option order. The server may hand the
  /// attributes back in a different key order (MySQL normalises JSON keys),
  /// so the variant's own [ProductVariant.label] can't be trusted for display.
  String variantLabel(ProductVariant v) {
    final ordered = [
      for (final o in options)
        if (v.attributes[o.name] != null) v.attributes[o.name]!,
    ];
    return ordered.isEmpty ? v.label : ordered.join(' / ');
  }

  /// The variant whose attributes equal [selection] exactly, or null.
  ProductVariant? findVariant(Map<String, String> selection) {
    if (selection.length != options.length) return null;
    for (final v in variants) {
      if (!v.isActive) continue;
      if (v.attributes.length != selection.length) continue;
      var match = true;
      for (final entry in selection.entries) {
        if (v.attributes[entry.key] != entry.value) {
          match = false;
          break;
        }
      }
      if (match) return v;
    }
    return null;
  }

  /// Whether any active variant with [name]=[value] still has stock, given
  /// the other picks so far — lets the picker grey out "L" once every L is
  /// gone, without greying out "L" just because red-L is.
  bool isValueAvailable(String name, String value, Map<String, String> otherPicks) {
    for (final v in variants) {
      if (!v.isActive || v.quantity <= 0) continue;
      if (v.attributes[name] != value) continue;
      var compatible = true;
      for (final entry in otherPicks.entries) {
        if (entry.key == name) continue;
        if (v.attributes[entry.key] != entry.value) {
          compatible = false;
          break;
        }
      }
      if (compatible) return true;
    }
    return false;
  }

  /// Lowest price across in-stock variants — what a card shows as "يبدأ من".
  double? get lowestVariantPrice {
    double? best;
    for (final v in variants) {
      final p = v.effectivePrice;
      if (p == null || !v.isActive) continue;
      if (best == null || p < best) best = p;
    }
    return best;
  }

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
      isFavorited: json['is_favorited'] as bool? ?? false,
      options: (json['options'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductOption.fromJson)
          .toList(),
      variants: (json['variants'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductVariant.fromJson)
          .toList(),
    );
  }
}

/// One axis of choice: `{"name": "اللون", "values": ["أحمر", "أزرق"]}`.
class ProductOption {
  final String name;
  final List<String> values;

  const ProductOption({required this.name, required this.values});

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    return ProductOption(
      name: json['name']?.toString() ?? '',
      values: (json['values'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'values': values};
}

/// One sellable combination, mirroring the backend's ItemVariant.
class ProductVariant {
  final int id;

  /// `{"اللون": "أحمر", "المقاس": "L"}` — keys are option names.
  final Map<String, String> attributes;
  final String sku;
  final int quantity;

  /// Override; null means the item's listing price applies.
  final double? price;

  /// Already resolved server-side: [price] if set, else the listing price.
  final double? effectivePrice;
  /// What the seller paid per unit. Only present when the viewer owns the
  /// item — the server strips it for everyone else.
  final double? costPrice;
  final String? imageUrl;
  final bool isActive;

  const ProductVariant({
    required this.id,
    required this.attributes,
    this.sku = '',
    required this.quantity,
    this.price,
    this.effectivePrice,
    this.costPrice,
    this.imageUrl,
    this.isActive = true,
  });

  bool get inStock => isActive && quantity > 0;

  /// 'أحمر / L'
  String get label => attributes.values.join(' / ');

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final rawAttrs = json['attributes'] as Map<String, dynamic>? ?? const {};
    return ProductVariant(
      id: json['id'] as int,
      attributes: rawAttrs.map((k, v) => MapEntry(k, v.toString())),
      sku: json['sku']?.toString() ?? '',
      quantity: json['quantity'] as int? ?? 0,
      price: _parseDouble(json['price']),
      effectivePrice: _parseDouble(json['effective_price']),
      costPrice: _parseDouble(json['cost_price']),
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}