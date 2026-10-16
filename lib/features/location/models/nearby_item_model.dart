import '../../../models/user.dart';
import 'location_model.dart';
import '../../../utils/item_condition.dart' as labels;

LocationModel? _parseLocation(dynamic json) {
  if (json == null) return null;
  try {
    return LocationModel.fromJson(json as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

class ItemCategory {
  final int id;
  final String name;
  final String slug;
  final int? parent;
  final String? icon;

  const ItemCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.parent,
    this.icon,
  });

  factory ItemCategory.fromJson(Map<String, dynamic> json) {
    return ItemCategory(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      parent: json['parent'] as int?,
      icon: json['icon'] as String?,
    );
  }
}

class ItemImage {
  final int id;
  final String image;
  final int order;
  final DateTime createdAt;

  const ItemImage({
    required this.id,
    required this.image,
    required this.order,
    required this.createdAt,
  });

  factory ItemImage.fromJson(Map<String, dynamic> json) {
    return ItemImage(
      id: json['id'] as int,
      image: json['image'] as String,
      order: json['order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class NearbyItem {
  final int id;
  final User owner;
  final User? currentHolder;
  final String title;
  final String description;
  final ItemCategory? category;
  final String condition;
  final int quantity;
  final String status;
  final LocationModel? currentLocation;
  final List<ItemImage> images;
  final double? distanceKm;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorited;

  const NearbyItem({
    required this.id,
    required this.owner,
    this.currentHolder,
    required this.title,
    required this.description,
    this.category,
    required this.condition,
    required this.quantity,
    required this.status,
    this.currentLocation,
    required this.images,
    this.distanceKm,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorited = false,
  });

  String? get firstImageUrl => images.isNotEmpty ? images.first.image : null;

  /// الاسم مؤهَّل بالبادئة لأن الـ getter يحمل اسم الدالة نفسه،
  /// فيحجبها داخل الصنف.
  String get conditionLabel => labels.conditionLabel(condition);

  String get distanceText =>
      distanceKm != null ? '${distanceKm!.toStringAsFixed(1)} كم' : '-- كم';

  factory NearbyItem.fromJson(Map<String, dynamic> json) {
    return NearbyItem(
      id: json['id'] as int,
      owner: User.fromJson(json['owner'] as Map<String, dynamic>),
      currentHolder: json['current_holder'] != null
          ? User.fromJson(json['current_holder'] as Map<String, dynamic>)
          : null,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] != null
          ? ItemCategory.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      condition: json['condition'] as String? ?? 'good',
      quantity: json['quantity'] as int? ?? 1,
      status: json['status'] as String? ?? 'active',
      currentLocation: _parseLocation(json['current_location']),
      images: ((json['images'] as List?) ?? [])
          .map((e) => ItemImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isFavorited: json['is_favorited'] as bool? ?? false,
    );
  }
}
