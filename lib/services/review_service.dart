import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../models/product_review.dart';
import 'api_client.dart';

class ReviewService {
  static const String _base = ApiConfig.baseUrl;
  final _client = ApiClient.instance;

  Future<List<ProductReview>> fetchReviews({
    required int itemId,
    int? minScore,
    int? maxScore,
    String ordering = '-created_at',
  }) async {
    final params = <String, String>{
      'item': '$itemId',
      'ordering': ordering,
    };
    if (minScore != null) params['min_score'] = '$minScore';
    if (maxScore != null) params['max_score'] = '$maxScore';

    // Public endpoint — no session to attach or refresh.
    final response = await _client.get(
      '/product-reviews/?${Uri(queryParameters: params).query}',
      auth: false,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (decoded['results'] as List<dynamic>?) ?? [];
      return results
          .cast<Map<String, dynamic>>()
          .map(ProductReview.fromJson)
          .toList();
    }
    throw Exception('فشل جلب التقييمات');
  }

  /// Returns null if the user has not reviewed the product yet (404).
  Future<ProductReview?> fetchMyReview({
    required int itemId,
    required String token,
  }) async {
    final response = await _client.get('/product-reviews/my-review/$itemId/');

    if (response.statusCode == 200) {
      return ProductReview.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } else if (response.statusCode == 404) {
      return null;
    } else if (response.statusCode == 401) {
      throw Exception('401');
    }
    throw Exception('فشل جلب تقييمي');
  }

  // Multipart image upload — kept on the raw http client directly since
  // ApiClient's silent-refresh-and-retry only knows how to replay a plain
  // JSON body, not resend an already-streamed file. Uncommon enough (a 401
  // has to land mid-review-submit) that this is an acceptable gap for now.
  Future<ProductReview> createReview({
    required String token,
    required int itemId,
    required int score,
    String? comment,
    XFile? image,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$_base/product-reviews/'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['item'] = '$itemId';
    request.fields['score'] = '$score';
    if (comment != null && comment.isNotEmpty) {
      request.fields['comment'] = comment;
    }
    if (image != null) {
      final bytes = await image.readAsBytes();
      request.files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: image.name));
    }

    final response = await http.Response.fromStream(await request.send());

    if (response.statusCode == 201) {
      return ProductReview.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throwApiError(response.statusCode, response.body);
    throw Exception('فشل إضافة التقييم');
  }

  Future<ProductReview> updateReview({
    required String token,
    required int reviewId,
    int? score,
    String? comment,
    XFile? image,
  }) async {
    final request = http.MultipartRequest(
        'PATCH', Uri.parse('$_base/product-reviews/$reviewId/'));
    request.headers['Authorization'] = 'Bearer $token';
    if (score != null) request.fields['score'] = '$score';
    if (comment != null) request.fields['comment'] = comment;
    if (image != null) {
      final bytes = await image.readAsBytes();
      request.files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: image.name));
    }

    final response = await http.Response.fromStream(await request.send());

    if (response.statusCode == 200) {
      return ProductReview.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throwApiError(response.statusCode, response.body);
    throw Exception('فشل تعديل التقييم');
  }

  Future<void> deleteReview({
    required String token,
    required int reviewId,
  }) async {
    final response = await _client.delete('/product-reviews/$reviewId/');

    if (response.statusCode == 204) return;
    _throwApiError(response.statusCode, response.body);
    throw Exception('فشل حذف التقييم');
  }

  void _throwApiError(int statusCode, String body) {
    if (statusCode == 401) throw Exception('401');
    if (statusCode == 403) throw Exception('403');
    if (statusCode == 500) throw Exception('500');
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final nonField = json['non_field_errors'];
      if (nonField is List && nonField.isNotEmpty) {
        throw Exception(nonField.first.toString());
      }
      final detail = json['detail'];
      if (detail != null) throw Exception(detail.toString());
      final first = json.values.first;
      if (first is List && first.isNotEmpty) {
        throw Exception(first.first.toString());
      }
    } catch (e) {
      if (e is Exception) rethrow;
    }
  }
}
