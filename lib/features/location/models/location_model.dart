import '../../../models/user.dart';

class LocationModel {
  final int id;
  final User user;
  final String locationType;
  final String name;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final double? latitude;
  final double? longitude;
  final String? contactPerson;
  final String? contactPhone;
  final String? notes;
  final bool isPrimary;
  final bool isActive;
  final String fullAddress;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocationModel({
    required this.id,
    required this.user,
    required this.locationType,
    required this.name,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    this.latitude,
    this.longitude,
    this.contactPerson,
    this.contactPhone,
    this.notes,
    required this.isPrimary,
    required this.isActive,
    required this.fullAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] as int,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      locationType: json['location_type'] as String? ?? 'other',
      name: json['name'] as String? ?? '',
      addressLine1: json['address_line1'] as String? ?? '',
      addressLine2: json['address_line2'] as String?,
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      postalCode: json['postal_code'] as String? ?? '',
      country: json['country'] as String? ?? '',
      // API returns lat/lng as strings — parse safely
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
      contactPerson: json['contact_person'] as String?,
      contactPhone: json['contact_phone'] as String?,
      notes: json['notes'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      fullAddress: json['full_address'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location_type': locationType,
      'name': name,
      'address_line1': addressLine1,
      if (addressLine2 != null) 'address_line2': addressLine2,
      'city': city,
      'state': state,
      'postal_code': postalCode,
      'country': country,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (contactPerson != null) 'contact_person': contactPerson,
      if (contactPhone != null) 'contact_phone': contactPhone,
      if (notes != null) 'notes': notes,
      'is_primary': isPrimary,
      'is_active': isActive,
    };
  }

  LocationModel copyWith({
    String? locationType,
    String? name,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    double? latitude,
    double? longitude,
    String? contactPerson,
    String? contactPhone,
    String? notes,
    bool? isPrimary,
    bool? isActive,
  }) {
    return LocationModel(
      id: id,
      user: user,
      locationType: locationType ?? this.locationType,
      name: name ?? this.name,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      contactPerson: contactPerson ?? this.contactPerson,
      contactPhone: contactPhone ?? this.contactPhone,
      notes: notes ?? this.notes,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
      fullAddress: fullAddress,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
