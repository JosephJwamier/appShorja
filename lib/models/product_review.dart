import '../utils/formatters.dart';

class ReviewerInfo {
  final int id;
  final String username;
  final String trustScore;
  final int totalSales;
  final bool identityVerified;
  final bool emailVerified;

  ReviewerInfo({
    required this.id,
    required this.username,
    required this.trustScore,
    this.totalSales = 0,
    this.identityVerified = false,
    this.emailVerified = false,
  });

  factory ReviewerInfo.fromJson(Map<String, dynamic> json) => ReviewerInfo(
        id: json['id'] as int? ?? 0,
        username: json['username'] as String? ?? '',
        trustScore: json['trust_score'] as String? ?? '0.00',
        totalSales: json['total_sales'] as int? ?? 0,
        identityVerified: json['identity_verified'] as bool? ?? false,
        emailVerified: json['email_verified'] as bool? ?? false,
      );
}

class ProductReview {
  final int id;
  final ReviewerInfo reviewer;
  final int item;
  final int score;
  final String? comment;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductReview({
    required this.id,
    required this.reviewer,
    required this.item,
    required this.score,
    this.comment,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    final raw = json['image_url'] as String? ?? json['image'] as String?;
    return ProductReview(
      id: json['id'] as int? ?? 0,
      reviewer: ReviewerInfo.fromJson(
          json['reviewer'] as Map<String, dynamic>? ?? {}),
      item: json['item'] as int? ?? 0,
      score: json['score'] as int? ?? 1,
      comment: (json['comment'] as String?)?.isEmpty == true
          ? null
          : json['comment'] as String?,
      imageUrl: (raw != null && raw.isNotEmpty) ? fixMediaUrl(raw) : null,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
