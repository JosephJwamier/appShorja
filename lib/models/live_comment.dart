class LiveComment {
  final int id;
  final int userId;
  final String username;
  final String content;
  final DateTime createdAt;

  LiveComment({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
  });

  factory LiveComment.fromJson(Map<String, dynamic> json) {
    return LiveComment(
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
