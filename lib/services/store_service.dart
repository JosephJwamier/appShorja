import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../models/store.dart';
import '../models/store_coupon.dart';
import '../models/coupon_collection.dart';
import '../models/followed_store_group.dart';
import '../config/api_config.dart';
import 'api_client.dart';

class StoreService {
  static const String baseUrl = ApiConfig.baseUrl;
  final _client = ApiClient.instance;

  // Multipart image upload — kept on the raw http client directly (see
  // note in review_service.dart for why).

  Future<({bool success, String message, Store? store})> createStore({
    required String accessToken,
    required String name,
    required String description,
    XFile? logo,
    XFile? cover,
    int? locationId,
    String? phoneNumber,
    String? whatsappNumber,
  }) async {
    final uri = Uri.parse('$baseUrl/stores/');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['name'] = name;
    request.fields['description'] = description;
    if (locationId != null) {
      request.fields['default_location_id'] = locationId.toString();
    }
    if (phoneNumber != null) {
      request.fields['phone_number'] = phoneNumber;
    }
    if (whatsappNumber != null) {
      request.fields['whatsapp_number'] = whatsappNumber;
    }

    if (logo != null) {
      final bytes = await logo.readAsBytes();
      final filename = logo.name;
      request.files.add(
        http.MultipartFile.fromBytes(
          'logo',
          bytes,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    if (cover != null) {
      final bytes = await cover.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'cover_image',
          bytes,
          filename: cover.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = data['success'] as bool? ?? false;
      final message =
          data['message'] as String? ??
          (success ? 'تمّ إنشاء المتجر' : 'فشل إنشاء المتجر');

      Store? store;
      if (success && data['data'] != null) {
        store = Store.fromJson(data['data'] as Map<String, dynamic>);
      }

      return (success: success, message: message, store: store);
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        store: null,
      );
    }
  }

  Future<({bool success, String message, Store? store})> updateStore({
    required String accessToken,
    required int storeId,
    required String name,
    required String description,
    required bool isActive,
    XFile? logo,
    XFile? cover,
    int? locationId,
    String? phoneNumber,
    String? whatsappNumber,
  }) async {
    final uri = Uri.parse('$baseUrl/stores/$storeId/');
    final request = http.MultipartRequest('PUT', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['name'] = name;
    request.fields['description'] = description;
    request.fields['is_active'] = isActive.toString();
    if (locationId != null) {
      request.fields['default_location_id'] = locationId.toString();
    }
    if (phoneNumber != null) {
      request.fields['phone_number'] = phoneNumber;
    }
    if (whatsappNumber != null) {
      request.fields['whatsapp_number'] = whatsappNumber;
    }

    if (logo != null) {
      final bytes = await logo.readAsBytes();
      final filename = logo.name;
      request.files.add(
        http.MultipartFile.fromBytes(
          'logo',
          bytes,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    if (cover != null) {
      final bytes = await cover.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'cover_image',
          bytes,
          filename: cover.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = data['success'] as bool? ?? false;
      final message =
          data['message'] as String? ??
          (success ? 'تمّ تحديث المتجر' : 'فشل تحديث المتجر');

      if (!success) {
        final detail = data['detail'] ?? data['error'] ?? data['errors'];
        return (
          success: false,
          message: detail?.toString() ?? message,
          store: null,
        );
      }

      Store? store;
      if (success && data['data'] != null) {
        store = Store.fromJson(data['data'] as Map<String, dynamic>);
      }

      return (success: success, message: message, store: store);
    } catch (_) {
      return (
        success: false,
        message: 'خطأ ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
        store: null,
      );
    }
  }

  /// Opens/closes the store via the dedicated toggle_active action, instead
  /// of bundling is_active into a full updateStore() multipart PUT (which
  /// re-validates and re-submits name/description/etc. just to flip a flag).
  Future<({bool success, String message})> toggleActive({
    required String accessToken,
    required int storeId,
    required bool isActive,
  }) async {
    final response = await _client.post(
      '/stores/$storeId/toggle_active/',
      body: {'is_active': isActive},
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      return (
        success: success,
        message: body['message'] as String? ??
            (success ? '' : 'تعذّر تحديث حالة المتجر'),
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  Future<Store?> fetchMyStore({required String accessToken}) async {
    final response = await _client.get('/stores/my_store/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['data'] == null) return null;
      return Store.fromJson(body['data'] as Map<String, dynamic>);
    } else if (response.statusCode == 404) {
      return null;
    }
    throw Exception('فشل جلب المتجر');
  }

  Future<List<Store>> fetchStores({
    required String accessToken,
    String? search,
  }) async {
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;

    final response =
        await _client.get('/stores/?${Uri(queryParameters: params).query}');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] ?? body['data'] ?? []) as List<dynamic>;
      return results
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('فشل جلب المتاجر');
  }

  Future<Store?> fetchStoreByUsername({
    required String accessToken,
    required String username,
  }) async {
    final response = await _client.get('/stores/public/$username/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['data'] == null) return null;
      return Store.fromJson(body['data'] as Map<String, dynamic>);
    } else if (response.statusCode == 404) {
      return null;
    }
    throw Exception('فشل جلب متجر البائع');
  }

  /// قراءة عامة: المسار مفتوح للضيوف، فالرمز اختياري.
  Future<Store?> fetchStoreById({
    String? accessToken,
    required int storeId,
  }) async {
    final response = await _client.get('/stores/$storeId/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] ?? body;
      return Store.fromJson(data as Map<String, dynamic>);
    } else if (response.statusCode == 404) {
      return null;
    }
    throw Exception('فشل جلب المتجر');
  }

  /// المتاجر التي يتابعها المستخدم الحالي، مع معاينة لمنتجات كل متجر
  Future<List<FollowedStoreGroup>> fetchFollowingStores({
    required String accessToken,
  }) async {
    final response = await _client.get('/stores/following/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] ?? []) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map((e) => FollowedStoreGroup.fromJson(e))
          .toList();
    }
    throw Exception(
      'فشل جلب المتاجر المتابَعة (${response.statusCode}): '
      '${response.body.length > 300 ? response.body.substring(0, 300) : response.body}',
    );
  }

  // ── المتابعة (follow / unfollow) ──────────────────────────────
  Future<({bool success, String message, bool isFollowing, int followersCount})>
      followStore({
    required String accessToken,
    required int storeId,
  }) async {
    final response = await _client.post('/stores/$storeId/follow/');
    return _parseFollowResponse(response, fallbackFollowing: true);
  }

  Future<({bool success, String message, bool isFollowing, int followersCount})>
      unfollowStore({
    required String accessToken,
    required int storeId,
  }) async {
    final response = await _client.post('/stores/$storeId/unfollow/');
    return _parseFollowResponse(response, fallbackFollowing: false);
  }

  ({bool success, String message, bool isFollowing, int followersCount})
      _parseFollowResponse(http.Response response,
          {required bool fallbackFollowing}) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      return (
        success: success,
        message: body['message'] as String? ?? '',
        isFollowing: body['is_following'] as bool? ?? fallbackFollowing,
        followersCount: body['followers_count'] as int? ?? 0,
      );
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        isFollowing: !fallbackFollowing,
        followersCount: 0,
      );
    }
  }

  // ── الكوبونات (coupons) ───────────────────────────────────────
  Future<List<StoreCoupon>> fetchStoreCoupons({
    required String accessToken,
    required int storeId,
  }) async {
    final response = await _client.get('/stores/$storeId/coupons/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] ?? []) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map((e) => StoreCoupon.fromJson(e))
          .toList();
    }
    return [];
  }

  /// كوبوناتي — كل الكوبونات التي جمعها المستخدم الحالي من كل المتاجر
  Future<List<CouponCollection>> fetchMyCoupons({
    required String accessToken,
  }) async {
    final response = await _client.get('/stores/my_coupons/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] ?? []) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map((e) => CouponCollection.fromJson(e))
          .toList();
    }
    return [];
  }

  Future<({bool success, String message})> collectCoupon({
    required String accessToken,
    required int storeId,
    required int couponId,
  }) async {
    final response = await _client.post('/stores/$storeId/coupons/$couponId/collect/');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        success: body['success'] as bool? ??
            (response.statusCode >= 200 && response.statusCode < 300),
        message: body['message'] as String? ?? '',
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  Future<({bool success, String message, StoreCoupon? coupon})> createCoupon({
    required String accessToken,
    required int storeId,
    required String code,
    required double amount,
    double minOrderAmount = 0,
    String description = '',
    bool isActive = true,
    DateTime? expiresAt,
  }) async {
    final response = await _client.post(
      '/stores/$storeId/coupons/',
      body: {
        'code': code,
        'amount': amount,
        'min_order_amount': minOrderAmount,
        'description': description,
        'is_active': isActive,
        'expires_at': expiresAt?.toIso8601String(),
      },
    );
    return _parseCouponResponse(response, fallback: 'تمّ إنشاء الكوبون');
  }

  Future<({bool success, String message, StoreCoupon? coupon})> updateCoupon({
    required String accessToken,
    required int storeId,
    required int couponId,
    String? code,
    double? amount,
    double? minOrderAmount,
    String? description,
    bool? isActive,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) async {
    final fields = <String, dynamic>{
      'code': ?code,
      'amount': ?amount,
      'min_order_amount': ?minOrderAmount,
      'description': ?description,
      'is_active': ?isActive,
      if (clearExpiresAt)
        'expires_at': null
      else if (expiresAt != null)
        'expires_at': expiresAt.toIso8601String(),
    };

    final response = await _client.patch(
      '/stores/$storeId/coupons/$couponId/',
      body: fields,
    );
    return _parseCouponResponse(response, fallback: 'تمّ تحديث الكوبون');
  }

  Future<({bool success, String message})> deleteCoupon({
    required String accessToken,
    required int storeId,
    required int couponId,
  }) async {
    final response = await _client.delete('/stores/$storeId/coupons/$couponId/');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        success: body['success'] as bool? ??
            (response.statusCode >= 200 && response.statusCode < 300),
        message: body['message'] as String? ?? '',
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  ({bool success, String message, StoreCoupon? coupon}) _parseCouponResponse(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ?? false;
      final message = body['message'] as String? ??
          (success ? fallback : 'فشلت العملية');
      if (!success) {
        final errors = body['errors'];
        return (
          success: false,
          message: errors != null ? errors.toString() : message,
          coupon: null,
        );
      }
      final data = body['data'] as Map<String, dynamic>?;
      return (
        success: true,
        message: message,
        coupon: data != null ? StoreCoupon.fromJson(data) : null,
      );
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        coupon: null,
      );
    }
  }
}
