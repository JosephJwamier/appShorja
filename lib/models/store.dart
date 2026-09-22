import '../config/api_config.dart';
import 'user.dart';

class Store {
  final int id;
  final User user;
  final String name;
  final String description;
  final String? logo;
  final String? logoUrl;
  final String? coverImage;
  final String? coverImageUrl;
  final bool isActive;
  final String? defaultLocation;
  final int? defaultLocationId;
  final String phoneNumber;
  final String whatsappNumber;
  final DateTime createdAt;
  final int totalItems;
  final int totalActiveItems;
  // --- storefront stats / follow ---
  final double rating;
  final bool isFollowing;
  final int followersCount;
  final double positiveReviewPercent;
  final double communicationRating;
  final int totalSold;

  /// Performance level ('' | bronze | silver | gold | diamond) and the full
  /// ordered badge list the server wants shown next to the name.
  final String level;
  final List<String> badges;
  // معرّف جلسة البث المباشر الحالية لهذا المتجر، أو null إن لم يكن يبثّ الآن.
  final int? liveSessionId;

  Store({
    required this.id,
    required this.user,
    required this.name,
    required this.description,
    this.logo,
    this.logoUrl,
    this.coverImage,
    this.coverImageUrl,
    required this.isActive,
    this.defaultLocation,
    this.defaultLocationId,
    this.phoneNumber = '',
    this.whatsappNumber = '',
    required this.createdAt,
    required this.totalItems,
    required this.totalActiveItems,
    this.rating = 0,
    this.isFollowing = false,
    this.followersCount = 0,
    this.positiveReviewPercent = 0,
    this.communicationRating = 0,
    this.totalSold = 0,
    this.level = '',
    this.badges = const [],
    this.liveSessionId,
  });

  bool get isLive => liveSessionId != null;

  /// Returns a copy with follow state (or active state, after toggle_active)
  /// overridden.
  Store copyWith({bool? isFollowing, int? followersCount, bool? isActive}) {
    return Store(
      id: id,
      user: user,
      name: name,
      description: description,
      logo: logo,
      logoUrl: logoUrl,
      coverImage: coverImage,
      coverImageUrl: coverImageUrl,
      isActive: isActive ?? this.isActive,
      defaultLocation: defaultLocation,
      defaultLocationId: defaultLocationId,
      phoneNumber: phoneNumber,
      whatsappNumber: whatsappNumber,
      createdAt: createdAt,
      totalItems: totalItems,
      totalActiveItems: totalActiveItems,
      rating: rating,
      isFollowing: isFollowing ?? this.isFollowing,
      followersCount: followersCount ?? this.followersCount,
      positiveReviewPercent: positiveReviewPercent,
      communicationRating: communicationRating,
      totalSold: totalSold,
      liveSessionId: liveSessionId,
    );
  }

  String? get fullLogoUrl {
    final raw = logoUrl ?? logo;
    if (raw == null) return null;
    if (raw.startsWith('http')) return raw;
    return '${ApiConfig.mediaBaseUrl}$raw';
  }

  String? get fullCoverUrl {
    final raw = coverImageUrl ?? coverImage;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${ApiConfig.mediaBaseUrl}$raw';
  }

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] as int,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      logo: json['logo'] as String?,
      logoUrl: json['logo_url'] as String?,
      coverImage: json['cover_image'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      phoneNumber: json['phone_number'] as String? ?? '',
      whatsappNumber: json['whatsapp_number'] as String? ?? '',
      defaultLocation: json['default_location'] is Map
          ? (json['default_location'] as Map<String, dynamic>)['full_address'] as String?
          : json['default_location'] as String?,
      defaultLocationId: json['default_location'] is Map
          ? (json['default_location'] as Map<String, dynamic>)['id'] as int?
          : json['default_location_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      totalItems: json['total_items'] as int? ?? 0,
      totalActiveItems: json['total_active_items'] as int? ?? 0,
      rating: _toDouble(json['rating']),
      isFollowing: json['is_following'] as bool? ?? false,
      followersCount: json['followers_count'] as int? ?? 0,
      positiveReviewPercent: _toDouble(json['positive_review_percent']),
      communicationRating: _toDouble(json['communication_rating']),
      totalSold: json['total_sold'] as int? ?? 0,
      level: json['level']?.toString() ?? '',
      badges: (json['badges'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      liveSessionId: json['live_session_id'] as int?,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}