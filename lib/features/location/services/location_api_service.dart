import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/location_model.dart';
import '../models/nearby_item_model.dart';
import '../models/nearby_store_model.dart';
import '../../../config/api_config.dart';

class LocationApiService {
  static const String _base = ApiConfig.baseUrl;

  Map<String, String> _authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // GET /api/locations/
  Future<List<LocationModel>> listLocations({
    required String token,
    String? city,
    String? country,
    String? locationType,
    bool? isPrimary,
  }) async {
    final params = <String, String>{};
    if (city != null) params['city'] = city;
    if (country != null) params['country'] = country;
    if (locationType != null) params['location_type'] = locationType;
    if (isPrimary != null) params['is_primary'] = isPrimary.toString();

    final uri = Uri.parse(
      '$_base/locations/',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _authHeaders(token));

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final List list = body is Map
          ? ((body['data'] ?? body['results']) as List? ?? [])
          : body as List;
      return list
          .map((e) => LocationModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwError(res.body, 'فشل تحميل المواقع');
  }

  // POST /api/locations/
  Future<void> createLocation({
    required String token,
    required Map<String, dynamic> data,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/locations/'),
      headers: _authHeaders(token),
      body: jsonEncode(data),
    );
    if (res.statusCode != 201) {
      _throwError(res.body, 'فشل إنشاء الموقع');
    }
  }

  // PATCH /api/locations/{id}/
  Future<void> updateLocation({
    required String token,
    required int id,
    required Map<String, dynamic> data,
  }) async {
    final res = await http.patch(
      Uri.parse('$_base/locations/$id/'),
      headers: _authHeaders(token),
      body: jsonEncode(data),
    );
    if (res.statusCode != 200) {
      _throwError(res.body, 'فشل تحديث الموقع');
    }
  }

  // DELETE /api/locations/{id}/
  Future<void> deleteLocation({required String token, required int id}) async {
    final res = await http.delete(
      Uri.parse('$_base/locations/$id/'),
      headers: _authHeaders(token),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      _throwError(res.body, 'فشل حذف الموقع');
    }
  }

  // POST /api/locations/{id}/set_primary/
  Future<void> setPrimaryLocation({
    required String token,
    required int id,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/locations/$id/set_primary/'),
      headers: _authHeaders(token),
      body: jsonEncode({}),
    );
    if (res.statusCode != 200) {
      _throwError(res.body, 'فشل تعيين الموقع الرئيسي');
    }
  }

  // GET /api/items/nearby/
  Future<List<NearbyItem>> getNearbyItems({
    required double lat,
    required double lng,
    double radius = 10,
    String? token,
  }) async {
    final uri = Uri.parse('$_base/locations/nearby_items/').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
      },
    );
    final headers = token != null
        ? _authHeaders(token)
        : const <String, String>{};
    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final List raw = body is Map
          ? ((body['data'] ?? body['results']) as List? ?? [])
          : body as List;
      return raw
          .map((e) => NearbyItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwError(res.body, 'فشل تحميل المنتجات القريبة [${res.statusCode}]');
  }

  // GET /api/locations/nearby_stores/
  Future<List<NearbyStore>> getNearbyStores({
    required double lat,
    required double lng,
    double radius = 10,
    String? token,
  }) async {
    final uri = Uri.parse('$_base/locations/nearby_stores/').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radius': radius.toString(),
      },
    );
    final headers = token != null
        ? _authHeaders(token)
        : const <String, String>{};
    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final List raw = body is Map
          ? ((body['data'] ?? body['results']) as List? ?? [])
          : body as List;
      return raw
          .map((e) => NearbyStore.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwError(res.body, 'فشل تحميل المتاجر القريبة [${res.statusCode}]');
  }

  // GET /api/items/?governorate=X — exact match against the fixed governorate
  // list (Location.state), unlike the free-text `city` field.
  Future<List<NearbyItem>> getItemsByGovernorate({
    required String governorate,
    String? country,
    String? status,
    String? condition,
    bool? hasLocation,
    String? token,
  }) async {
    final params = <String, String>{'governorate': governorate};
    if (country != null) params['country'] = country;
    if (status != null) params['status'] = status;
    if (condition != null) params['condition'] = condition;
    if (hasLocation != null) params['has_location'] = hasLocation.toString();

    final uri = Uri.parse('$_base/items/').replace(queryParameters: params);
    final headers = token != null
        ? _authHeaders(token)
        : const <String, String>{};
    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final List results = body is Map
          ? ((body['data'] ?? body['results']) as List? ?? [])
          : body as List;
      return results
          .map((e) => NearbyItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwError(res.body, 'فشل تحميل المنتجات');
  }

  // GET /api/stores/?governorate=X
  Future<List<NearbyStore>> getStoresByGovernorate({
    required String governorate,
    String? token,
  }) async {
    final uri = Uri.parse(
      '$_base/stores/',
    ).replace(queryParameters: {'governorate': governorate});
    final headers = token != null
        ? _authHeaders(token)
        : const <String, String>{};
    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final List results = body is Map
          ? ((body['data'] ?? body['results']) as List? ?? [])
          : body as List;
      return results
          .map((e) => NearbyStore.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _throwError(res.body, 'فشل تحميل المتاجر');
  }

  Never _throwError(String body, String fallback) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data.containsKey('message')) throw Exception(data['message']);
      final first = data.entries.first;
      final msg = (first.value is List) ? first.value.first : first.value;
      throw Exception(msg.toString());
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(fallback);
    }
  }
}
