import '../config/api_config.dart';

class User {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final bool emailVerified;
  final bool phoneVerified;
  final double trustScore;
  final String? avatarUrl;
  final String bio;
  final DateTime? dateOfBirth;

  /// Badge kinds of this user's store (founder, verified, gold…), in the
  /// server's display order. Empty for users without a store.
  final List<String> storeBadges;

  User({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
    required this.email,
    required this.phone,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.trustScore = 0,
    this.avatarUrl,
    this.bio = '',
    this.dateOfBirth,
    this.storeBadges = const [],
  });

  /// الاسم الأول + الثاني إن أدخلهما المستخدم، وإلا اسم المستخدم — يُستخدم
  /// بدل username في أي مكان يُعرَّف فيه المستخدم بالواجهة (تبويب الحساب، إلخ).
  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : username;
  }

  /// نفس نمط تحويل الرابط النسبي لمطلق المستخدم في Store.fullLogoUrl.
  String? get fullAvatarUrl {
    final raw = avatarUrl;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${ApiConfig.mediaBaseUrl}$raw';
  }

  User copyWith({
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    bool? emailVerified,
    bool? phoneVerified,
    String? avatarUrl,
    String? bio,
    DateTime? dateOfBirth,
  }) =>
      User(
        id: id,
        username: username ?? this.username,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        emailVerified: emailVerified ?? this.emailVerified,
        phoneVerified: phoneVerified ?? this.phoneVerified,
        trustScore: trustScore,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        storeBadges: storeBadges,
      );

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      emailVerified: json['email_verified'] as bool? ?? false,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      trustScore: double.tryParse(json['trust_score']?.toString() ?? '') ?? 0,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String? ?? '',
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'] as String)
          : null,
      storeBadges: (json['store_badges'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'phone': phone,
    'email_verified': emailVerified,
    'phone_verified': phoneVerified,
    'trust_score': trustScore,
    'avatar_url': avatarUrl,
    'bio': bio,
    'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
  };
}
