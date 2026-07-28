import 'dart:convert';
import '../models/category.dart';
import 'api_client.dart';

class CategoryService {
  final _client = ApiClient.instance;

  // accessToken is kept for call-site compatibility — ApiClient tracks the
  // live token itself (and silently refreshes it on a 401).
  Future<List<Category>> fetchCategories({
    required String accessToken,
  }) async {
    return _fetch();
  }

  /// Fetches root-level categories (parent=null).
  Future<List<Category>> fetchRootCategories({
    required String accessToken,
  }) async {
    return _fetch(parentParam: 'null');
  }

  /// Fetches sub-categories for the given [parentId].
  Future<List<Category>> fetchSubCategories({
    required String accessToken,
    required int parentId,
  }) async {
    return _fetch(parentParam: '$parentId');
  }

  Future<List<Category>> _fetch({String? parentParam}) async {
    final query = parentParam != null ? '?parent=$parentParam' : '';

    final response = await _client.get('/categories/$query');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List<dynamic> list = body is Map
          ? (body['results'] as List? ?? body['data'] as List? ?? [])
          : body as List;
      return list
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (response.statusCode == 401) {
      throw Exception('الجلسة منتهية، سجّل دخولاً من جديد');
    } else {
      throw Exception('فشل جلب الفئات');
    }
  }
}
