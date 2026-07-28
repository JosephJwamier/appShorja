class StoreReviewerInfo {
  final int id;
  final String username;
  final double trustScore;

  StoreReviewerInfo({
    required this.id,
    required this.username,
    this.trustScore = 0,
  });

  factory StoreReviewerInfo.fromJson(Map<String, dynamic> json) =>
      StoreReviewerInfo(
        id: json['id'] as int? ?? 0,
        username: json['username'] as String? ?? '',
        trustScore: _toDouble(json['trust_score']),
      );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class StoreReview {
  final int id;
  final StoreReviewerInfo reviewer;
  final int store;
  final int score;
  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;

  StoreReview({
    required this.id,
    required this.reviewer,
    required this.store,
    required this.score,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoreReview.fromJson(Map<String, dynamic> json) {
    return StoreReview(
      id: json['id'] as int? ?? 0,
      reviewer: StoreReviewerInfo.fromJson(
          json['reviewer'] as Map<String, dynamic>? ?? {}),
      store: json['store'] as int? ?? 0,
      score: json['score'] as int? ?? 1,
      comment: json['comment'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}
