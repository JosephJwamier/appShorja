/// A signed-in user who has watched a live session — returned only to the
/// session's store owner or a session moderator (see LiveSessionService
/// .fetchViewers). is_moderator/is_banned reflect this specific session
/// only, never the store's other broadcasts.
class LiveSessionViewer {
  final int userId;
  final String username;
  final bool isWatching;
  final bool isModerator;
  final bool isBanned;
  final DateTime joinedAt;
  final DateTime lastSeenAt;

  LiveSessionViewer({
    required this.userId,
    required this.username,
    required this.isWatching,
    required this.isModerator,
    required this.isBanned,
    required this.joinedAt,
    required this.lastSeenAt,
  });

  factory LiveSessionViewer.fromJson(Map<String, dynamic> json) {
    return LiveSessionViewer(
      userId: json['user_id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      isWatching: json['is_watching'] as bool? ?? false,
      isModerator: json['is_moderator'] as bool? ?? false,
      isBanned: json['is_banned'] as bool? ?? false,
      joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? '') ?? DateTime.now(),
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  LiveSessionViewer copyWith({bool? isModerator, bool? isBanned}) {
    return LiveSessionViewer(
      userId: userId,
      username: username,
      isWatching: isWatching,
      isModerator: isModerator ?? this.isModerator,
      isBanned: isBanned ?? this.isBanned,
      joinedAt: joinedAt,
      lastSeenAt: lastSeenAt,
    );
  }
}
