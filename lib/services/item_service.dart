import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/filter_params.dart';
import '../models/listing.dart';
import '../models/product.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import 'api_client.dart';

class ItemService {
  static const String baseUrl = ApiConfig.baseUrl;
  final _client = ApiClient.instance;

  Future<List<FixedListing>> fetchFixedListings({
    required String accessToken,
  }) async {
    final response = await _client.get('/listings/fixed/');

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw Exception('فشل جلب العروض');
      final results = decoded['results'] as List<dynamic>;
      return results
          .cast<Map<String, dynamic>>()
          .map((e) => FixedListing.fromJson(e))
          .toList();
    } else if (response.statusCode == 401) {
      throw Exception('الجلسة منتهية، سجّل دخولاً من جديد');
    } else {
      throw Exception('فشل جلب العروض');
    }
  }

  Future<FixedListing?> fetchListingById({
    required String accessToken,
    required int listingId,
  }) async {
    final response = await _client.get('/listings/fixed/$listingId/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return FixedListing.fromJson(body);
    }
    return null;
  }

  Future<FixedListing?> fetchListingByItemId({
    required String accessToken,
    required int itemId,
  }) async {
    final response =
        await _client.get('/listings/fixed/?item=$itemId&page_size=100');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] as List?) ?? [];
      // لا نعتمد على أن الخادم قد صفّى النتائج فعلاً حسب "item" (بعض
      // نقاط النهاية تتجاهل معاملات الاستعلام غير المعرَّفة وتُعيد
      // الصفحة الافتراضية كاملة) — لذا نطابق العنصر يدوياً بمعرّفه
      // لتفادي فتح تفاصيل منتج مغاير لما ضغط عليه المستخدم.
      for (final r in results) {
        final map = r as Map<String, dynamic>;
        final itemJson = map['item'] as Map<String, dynamic>?;
        if (itemJson != null && itemJson['id'] == itemId) {
          return FixedListing.fromJson(map);
        }
      }
    }
    return null;
  }

  /// Personalized feed ranked by the current user's category interests
  /// (from onboarding + purchases/follows), with popular items filling out
  /// the rest of the page. Same paginated shape as [fetchFixedListingsPaginated]
  /// so both the home-screen preview and the "عرض الكل" screen can share it.
  /// Returns an empty/no-more result on failure — this is a "nice to have"
  /// section, never something that should block the home feed.
  Future<({List<FixedListing> listings, bool hasMore})>
      fetchRecommendedListingsPaginated({
    required String accessToken,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _client.get(
      '/listings/fixed/recommended/?page=$page&page_size=$pageSize',
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return (listings: <FixedListing>[], hasMore: false);
      final results = decoded['results'] as List<dynamic>;
      return (
        listings: results
            .cast<Map<String, dynamic>>()
            .map((e) => FixedListing.fromJson(e))
            .toList(),
        hasMore: decoded['next'] != null,
      );
    }
    return (listings: <FixedListing>[], hasMore: false);
  }

  Future<List<FixedListing>> fetchSimilarListings({
    required String accessToken,
    required int listingId,
    int limit = 10,
  }) async {
    final response =
        await _client.get('/listings/fixed/$listingId/similar/?limit=$limit');

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw Exception('فشل جلب المنتجات المشابهة');
      return decoded
          .cast<Map<String, dynamic>>()
          .map((e) => FixedListing.fromJson(e))
          .toList();
    } else if (response.statusCode == 401) {
      throw Exception('الجلسة منتهية، سجّل دخولاً من جديد');
    } else {
      throw Exception('فشل جلب المنتجات المشابهة');
    }
  }

  // Multipart (image upload) endpoints below are kept on the raw http
  // client directly — ApiClient's silent-refresh-and-retry only knows how
  // to replay a plain JSON body, not resend an already-streamed file.

  Future<int> createItem({
    required String accessToken,
    required String title,
    required String description,
    required int categoryId,
    required String condition,
    required int quantity,
    required List<XFile> images,
    String packageSize = 'medium',
    int warrantyDays = 7,
    int? locationId,
  }) async {
    final uri = Uri.parse('$baseUrl/items/');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';

    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['category'] = categoryId.toString();
    request.fields['condition'] = condition;
    request.fields['quantity'] = quantity.toString();
    request.fields['package_size'] = packageSize;
    request.fields['warranty_days'] = warrantyDays.toString();
    if (locationId != null) {
      request.fields['current_location_id'] = locationId.toString();
    }

    for (final image in images) {
      final bytes = await image.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes('images', bytes, filename: image.name),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] ?? body;
      return data['id'] as int;
    } else {
      final body = response.body;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final msg = json['message'] ?? json['detail'] ?? json.values.first;
        throw Exception(msg.toString());
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('فشل رفع المنتج [${response.statusCode}]');
      }
    }
  }

  Future<void> createFixedListing({
    required String accessToken,
    required int itemId,
    required double price,
    required double depositPercentage,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/create_fixed_listing/');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['price'] = price.toString();
    request.fields['deposit_percentage'] = depositPercentage.toString();

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('فشل نشر المنتج للبيع');
    }
  }

  Future<void> updateFixedListing({
    required String accessToken,
    required int itemId,
    required double price,
    double? originalPrice,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/update_fixed_listing/');
    final request = http.MultipartRequest('PATCH', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['price'] = price.toString();
    if (originalPrice != null) {
      request.fields['original_price'] = originalPrice.toString();
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 202) {
      final body = response.body;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final msg = json['message'] ?? json['detail'] ?? json.values.first;
        throw Exception(msg.toString());
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('فشل تحديث السعر [${response.statusCode}]');
      }
    }
  }

  Future<List<Product>> fetchMyItems({
    required String accessToken,
    required int ownerId,
  }) async {
    final response = await _client.get('/items/?owner=$ownerId');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return results
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('فشل جلب منتجاتي');
    }
  }

  Future<void> createAuction({
    required String accessToken,
    required int itemId,
    required double startingPrice,
    required double minimumIncrement,
    required double bidDeposit,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/create_auction/');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['starting_price'] = startingPrice.toString();
    request.fields['minimum_increment'] = minimumIncrement.toString();
    request.fields['bid_deposit'] = bidDeposit.toString();
    request.fields['start_time'] = startTime.toUtc().toIso8601String();
    request.fields['end_time'] = endTime.toUtc().toIso8601String();

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('فشل إنشاء المزاد');
    }
  }

  Future<void> updateAuction({
    required String accessToken,
    required int itemId,
    required int auctionId,
    required double startingPrice,
    required double minimumIncrement,
    required double bidDeposit,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final uri =
        Uri.parse('$baseUrl/items/$itemId/update_auction/$auctionId/');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['starting_price'] = startingPrice.toString();
    request.fields['minimum_increment'] = minimumIncrement.toString();
    request.fields['bid_deposit'] = bidDeposit.toString();
    request.fields['start_time'] = startTime.toUtc().toIso8601String();
    request.fields['end_time'] = endTime.toUtc().toIso8601String();

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = response.body;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final msg = json['message'] ?? json['detail'] ?? json.values.first;
        throw Exception(msg.toString());
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('فشل تعديل المزاد [${response.statusCode}]');
      }
    }
  }

  Future<List<Product>> fetchItemsByStoreUsername({
    required String accessToken,
    required String username,
  }) async {
    final response = await _client
        .get('/stores/public/$username/items/?include_transferred=true');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] ?? []) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map((e) => Product.fromJson(e))
          .toList();
    }
    throw Exception('فشل جلب منتجات المتجر');
  }

  /// Items from stores the current user follows (home feed).
  Future<List<Product>> fetchFollowingItems({
    required String accessToken,
  }) async {
    final response = await _client.get('/stores/following-items/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (body['data'] ?? []) as List<dynamic>;
      return data
          .cast<Map<String, dynamic>>()
          .map((e) => Product.fromJson(e))
          .toList();
    }
    return [];
  }

  Future<({List<FixedListing> listings, bool hasMore})>
      fetchFixedListingsPaginated({
    required String accessToken,
    int page = 1,
    int pageSize = 20,
    FilterParams filters = FilterParams.empty,
    String? search,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'page_size': '$pageSize',
    };
    params.addAll(filters.toQueryParams());
    if (search != null && search.isNotEmpty) params['search'] = search;

    final response =
        await _client.get('/listings/fixed/?${Uri(queryParameters: params).query}');

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw Exception('فشل جلب العروض');
      final results = decoded['results'] as List<dynamic>;
      return (
        listings: results
            .cast<Map<String, dynamic>>()
            .map((e) => FixedListing.fromJson(e))
            .toList(),
        hasMore: decoded['next'] != null,
      );
    } else if (response.statusCode == 401) {
      throw Exception('الجلسة منتهية، سجّل دخولاً من جديد');
    } else {
      throw Exception('فشل جلب العروض');
    }
  }

  Future<void> updateItem({
    required String accessToken,
    required int itemId,
    required String title,
    required String description,
    required int categoryId,
    required String condition,
    required int quantity,
    String packageSize = 'medium',
    int warrantyDays = 7,
    int? locationId,
    List<XFile> newImages = const [],
    List<int> removeImageIds = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/items/$itemId/');
    final request = http.MultipartRequest('PATCH', uri);

    request.headers['Authorization'] = 'Bearer $accessToken';

    request.fields['title'] = title;
    request.fields['description'] = description;
    request.fields['category'] = categoryId.toString();
    request.fields['condition'] = condition;
    request.fields['quantity'] = quantity.toString();
    request.fields['package_size'] = packageSize;
    request.fields['warranty_days'] = warrantyDays.toString();
    if (locationId != null) {
      request.fields['current_location_id'] = locationId.toString();
    }
    if (removeImageIds.isNotEmpty) {
      request.fields['remove_image_ids'] = removeImageIds.join(',');
    }

    for (final image in newImages) {
      final bytes = await image.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes('images', bytes, filename: image.name),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200 && response.statusCode != 202) {
      final body = response.body;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final msg = json['message'] ?? json['detail'] ?? json.values.first;
        throw Exception(msg.toString());
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('فشل تعديل المنتج [${response.statusCode}]');
      }
    }
  }

  Future<void> deleteItem({
    required String accessToken,
    required int itemId,
  }) async {
    final response = await _client.delete('/items/$itemId/');

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('فشل حذف المنتج');
    }
  }
}
