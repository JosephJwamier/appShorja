import '../../../config/api_config.dart';
import '../../../models/user.dart';
import 'location_model.dart';

LocationModel? _parseLocation(dynamic json) {
  if (json == null) return null;
  try {
    return LocationModel.fromJson(json as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

class NearbyStore {
  final int id;
  final User user;
  final String name;
  final String description;
  final String? logo;
  final String? logoUrl;
  final bool isActive;
  final LocationModel? defaultLocation;
  final DateTime createdAt;
  final int totalItems;
  final int totalActiveItems;
  final double? distanceKm;

  const NearbyStore({
    required this.id,
    required this.user,
    required this.name,
    required this.description,
    this.logo,
    this.logoUrl,
    required this.isActive,
    this.defaultLocation,
    required this.createdAt,
    required this.totalItems,
    required this.totalActiveItems,
    this.distanceKm,
  });

  String? get fullLogoUrl {
    final raw = logoUrl ?? logo;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${ApiConfig.mediaBaseUrl}$raw';
  }

  String get distanceText =>
      distanceKm != null ? '${distanceKm!.toStringAsFixed(1)} كم' : '-- كم';

  factory NearbyStore.fromJson(Map<String, dynamic> json) {
    return NearbyStore(
      id: json['id'] as int,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      logo: json['logo'] as String?,
      logoUrl: json['logo_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      defaultLocation: _parseLocation(json['default_location']),
      createdAt: DateTime.parse(json['created_at'] as String),
      totalItems: json['total_items'] as int? ?? 0,
      totalActiveItems: json['total_active_items'] as int? ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
    );
  }
}
