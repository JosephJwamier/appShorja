class User {
  final int id;
  final String username;
  final String email;
  final String phone;
  final bool emailVerified;
  final bool phoneVerified;
  final double trustScore;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.trustScore = 0,
  });

  User copyWith({
    String? username,
    String? email,
    String? phone,
    bool? emailVerified,
    bool? phoneVerified,
  }) =>
      User(
        id: id,
        username: username ?? this.username,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        emailVerified: emailVerified ?? this.emailVerified,
        phoneVerified: phoneVerified ?? this.phoneVerified,
        trustScore: trustScore,
      );

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      emailVerified: json['email_verified'] as bool? ?? false,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      trustScore: double.tryParse(json['trust_score']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'email': email,
    'phone': phone,
    'email_verified': emailVerified,
    'phone_verified': phoneVerified,
    'trust_score': trustScore,
  };
}