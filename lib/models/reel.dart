/// Lightweight ref to the store that posted a reel — mirrors LiveStoreRef
/// (lib/models/live_session.dart), which itself mirrors the backend's
/// PublicUserStoreSerializer shape (NOT the full Store model).
class ReelStoreRef {
  final int id;
  final String name;
  final String? logoUrl;
  final String ownerUsername;

  ReelStoreRef({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.ownerUsername,
  });

  factory ReelStoreRef.fromJson(Map<String, dynamic> json) {
    return ReelStoreRef(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      ownerUsername: json['owner_username'] as String? ?? '',
    );
  }
}

/// Minimal summary of the single product a reel can tag (shoppable video) —
/// just enough to render a tappable chip in the overlay; the full listing
/// (price/deposit/etc.) is fetched separately via ItemService when the chip
/// is tapped, same as any other product-details navigation in the app.
class ReelItemRef {
  final int id;
  final String title;
  final String? imageUrl;
  final double? price;

  ReelItemRef({
    required this.id,
    required this.title,
    this.imageUrl,
    this.price,
  });

  factory ReelItemRef.fromJson(Map<String, dynamic> json) {
    return ReelItemRef(
      id: json['id'] as int,
      title: (json['title'] ?? json['name']) as String? ?? '',
      imageUrl: (json['image'] ?? json['image_url']) as String?,
      price: json['price'] != null ? _toDouble(json['price']) : null,
    );
  }
}

/// A comment on a reel — identical shape to LiveComment
/// (lib/models/live_comment.dart), since ReelComment is a direct backend
/// copy of LiveSessionComment (see the reels plan).
class ReelComment {
  final int id;
  final int userId;
  final String username;
  final String content;
  final DateTime createdAt;

  ReelComment({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
  });

  factory ReelComment.fromJson(Map<String, dynamic> json) {
    return ReelComment(
      id: json['id'] as int,
      userId: json['user_id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class Reel {
  final int id;
  final ReelStoreRef store;
  final String caption;
  final String videoUrl;
  final String? thumbnailUrl;
  final ReelItemRef? item;
  final int durationSeconds;
  final int viewCount;
  final int likesCount;
  final int commentsCount;
  final bool isLikedByMe;
  // pending_upload / published / failed / archived — my_reels shows every
  // status, the public feed only ever returns 'published'.
  final String status;
  final DateTime createdAt;

  Reel({
    required this.id,
    required this.store,
    required this.caption,
    required this.videoUrl,
    this.thumbnailUrl,
    this.item,
    required this.durationSeconds,
    required this.viewCount,
    required this.likesCount,
    required this.commentsCount,
    required this.isLikedByMe,
    this.status = 'published',
    required this.createdAt,
  });

  bool get isPublished => status == 'published';
  bool get hasTaggedItem => item != null;

  /// [clearItem] exists because `item: null` is indistinguishable from "not
  /// passed" in Dart's named-argument model — and removing a reel's product
  /// tag is exactly the case the edit screen needs to express.
  Reel copyWith({
    bool? isLikedByMe,
    int? likesCount,
    int? commentsCount,
    int? viewCount,
    String? status,
    String? caption,
    ReelItemRef? item,
    bool clearItem = false,
  }) {
    return Reel(
      id: id,
      store: store,
      caption: caption ?? this.caption,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      item: clearItem ? null : (item ?? this.item),
      durationSeconds: durationSeconds,
      viewCount: viewCount ?? this.viewCount,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  factory Reel.fromJson(Map<String, dynamic> json) {
    final storeJson = json['store'] as Map<String, dynamic>?;
    final itemJson = json['item'] as Map<String, dynamic>?;
    return Reel(
      id: json['id'] as int,
      store: storeJson != null
          ? ReelStoreRef.fromJson(storeJson)
          : ReelStoreRef(id: 0, name: '', ownerUsername: ''),
      caption: json['caption'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      item: itemJson != null ? ReelItemRef.fromJson(itemJson) : null,
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      viewCount: json['view_count'] as int? ?? 0,
      likesCount: json['likes_count'] as int? ?? 0,
      commentsCount: json['comments_count'] as int? ?? 0,
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
      status: json['status'] as String? ?? 'published',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
