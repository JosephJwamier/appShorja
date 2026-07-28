import 'dart:convert';
import '../models/store_review.dart';
import 'api_client.dart';

class StoreReviewService {
  final _client = ApiClient.instance;

  Future<({List<StoreReview> results, String? next, int count})>
      fetchReviews({
    required int storeId,
    int? minScore,
    int? maxScore,
    String ordering = '-created_at',
    String? pageUrl,
  }) async {
    final path = pageUrl ??
        '/store-reviews/?${Uri(queryParameters: {
              'store': '$storeId',
              'ordering': ordering,
              if (minScore != null) 'min_score': '$minScore',
              if (maxScore != null) 'max_score': '$maxScore',
            }).query}';

    // Public endpoint — no session to attach or refresh.
    final response = await _client.get(path, auth: false);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final results = ((decoded['results'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(StoreReview.fromJson)
          .toList();
      return (
        results: results,
        next: decoded['next'] as String?,
        count: decoded['count'] as int? ?? results.length,
      );
    }
    throw Exception('فشل جلب تقييمات المتجر');
  }

  /// Returns null if the current user has not reviewed this store yet (404).
  Future<StoreReview?> fetchMyReview({
    required int storeId,
    required String token,
  }) async {
    final response = await _client.get('/store-reviews/my-review/$storeId/');

    if (response.statusCode == 200) {
      return StoreReview.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } else if (response.statusCode == 404) {
      return null;
    } else if (response.statusCode == 401) {
      throw Exception('401');
    }
    throw Exception('فشل جلب تقييمي');
  }

  Future<StoreReview> createReview({
    required String token,
    required int storeId,
    required int score,
    String? comment,
  }) async {
    final response = await _client.post(
      '/store-reviews/',
      body: {
        'store': storeId,
        'score': score,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );

    if (response.statusCode == 201) {
      return StoreReview.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throwApiError(response.statusCode, response.body);
    throw Exception('فشل إضافة التقييم');
  }

  Future<StoreReview> updateReview({
    required String token,
    required int reviewId,
    int? score,
    String? comment,
  }) async {
    final response = await _client.patch(
      '/store-reviews/$reviewId/',
      body: {
        'score': ?score,
        'comment': ?comment,
      },
    );

    if (response.statusCode == 200) {
      return StoreReview.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    _throwApiError(response.statusCode, response.body);
    throw Exception('فشل تعديل التقييم');
  }

  Future<void> deleteReview({
    required String token,
    required int reviewId,
  }) async {
    final response = await _client.delete('/store-reviews/$reviewId/');

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
