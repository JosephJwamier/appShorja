import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/representative_request.dart';
import '../models/representative_reservation.dart';
import 'api_client.dart';

class RepresentativeService {
  final _client = ApiClient.instance;

  Future<({bool success, String message, RepresentativeRequest? request})>
  createRequest({
    required String accessToken,
    required int itemId,
    required double commissionPercentage,
    required bool canList,
    required bool canNegotiate,
    required bool canCompleteSale,
    required String requestMessage,
  }) async {
    final response = await _client.post(
      '/representatives/create_request/',
      body: {
        'item_id': itemId,
        'commission_percentage': commissionPercentage.toString(),
        'can_list': canList,
        'can_negotiate': canNegotiate,
        'can_complete_sale': canCompleteSale,
        'request_message': requestMessage,
      },
    );

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = data['success'] as bool? ?? false;
      final message =
          data['message'] as String? ??
          (success ? 'تمّ إرسال الطلب' : 'فشل إرسال الطلب');

      RepresentativeRequest? request;
      if (success && data['data'] != null) {
        request = RepresentativeRequest.fromJson(
          data['data'] as Map<String, dynamic>,
        );
      }

      return (success: success, message: message, request: request);
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        request: null,
      );
    }
  }

  Future<List<RepresentativeRequest>> fetchReceivedRequests({
    required String accessToken,
  }) async {
    final response = await _client.get('/representatives/received_requests/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['data'] as List<dynamic>;
      return list
          .map(
            (item) =>
                RepresentativeRequest.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } else {
      throw Exception('فشل جلب الطلبات الواردة');
    }
  }

  Future<({bool success, String message, RepresentativeRequest? request})>
  acceptRequest({required String accessToken, required int requestId}) async {
    final response =
        await _client.post('/representatives/$requestId/accept/', body: {});

    return _parseActionResponse(response, successDefault: 'تمّ القبول');
  }

  Future<({bool success, String message, RepresentativeRequest? request})>
  rejectRequest({
    required String accessToken,
    required int requestId,
    required String rejectionReason,
  }) async {
    final response = await _client.post(
      '/representatives/$requestId/reject/',
      body: {'rejection_reason': rejectionReason},
    );

    return _parseActionResponse(response, successDefault: 'تمّ الرفض');
  }

  ({bool success, String message, RepresentativeRequest? request})
  _parseActionResponse(
    http.Response response, {
    required String successDefault,
  }) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = data['success'] as bool? ?? false;
      final message =
          data['message'] as String? ??
          (success ? successDefault : 'فشلت العمليّة');

      RepresentativeRequest? request;
      if (success && data['data'] != null) {
        request = RepresentativeRequest.fromJson(
          data['data'] as Map<String, dynamic>,
        );
      }

      return (success: success, message: message, request: request);
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        request: null,
      );
    }
  }

  Future<List<RepresentativeRequest>> fetchActiveRepresentatives({
    required String accessToken,
  }) async {
    final response = await _client.get('/representatives/active/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['data'] as List<dynamic>;
      return list
          .map(
            (item) =>
                RepresentativeRequest.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } else {
      throw Exception('فشل جلب المندوبيّات النشطة');
    }
  }

  Future<List<RepresentativeRequest>> fetchSentRequests({
    required String accessToken,
  }) async {
    final response = await _client.get('/representatives/sent_requests/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final list = body['data'] as List<dynamic>;
      return list
          .map(
            (item) =>
                RepresentativeRequest.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } else {
      throw Exception('فشل جلب الطلبات المرسلة');
    }
  }

  Future<({bool success, String message, RepresentativeRequest? request})>
  cancelRequest({required String accessToken, required int requestId}) async {
    final response =
        await _client.post('/representatives/$requestId/cancel/', body: {});

    return _parseActionResponse(response, successDefault: 'تمّ الإلغاء');
  }

  Future<bool> deleteRequest({
    required String accessToken,
    required int requestId,
  }) async {
    final response = await _client.delete('/representatives/$requestId/');

    return response.statusCode == 204 || response.statusCode == 200;
  }

  Future<
      ({
        bool success,
        String message,
        RepresentativeReservation? reservation,
      })> createReservationForBuyer({
    required String accessToken,
    required int representativeAssignmentId,
    required CreateReservationRequest request,
  }) async {
    final response = await _client.post(
      '/representatives/$representativeAssignmentId/create_reservation_for_buyer/',
      body: request.toJson(),
    );

    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 201) {
      if (body == null) {
        return (
          success: false,
          message: 'استجابة غير متوقّعة من الخادم',
          reservation: null,
        );
      }
      try {
        return (
          success: true,
          message: body['message'] as String? ?? 'تمّ إنشاء الحجز بنجاح',
          reservation: RepresentativeReservation.fromJson(body),
        );
      } catch (_) {
        return (
          success: false,
          message: 'تعذّر قراءة بيانات الحجز من الخادم',
          reservation: null,
        );
      }
    }

    if (body == null) {
      return (
        success: false,
        message: 'فشل إنشاء الحجز [${response.statusCode}]',
        reservation: null,
      );
    }

    return (
      success: false,
      message: _extractErrorMessage(body, response.statusCode),
      reservation: null,
    );
  }

  String _extractErrorMessage(Map<String, dynamic> body, int statusCode) {
    final errors = body['errors'];
    if (errors is Map) {
      final flattened = errors.values
          .expand((v) => v is List ? v.map((e) => e.toString()) : [v.toString()])
          .join('\n');
      if (flattened.isNotEmpty) return flattened;
    }

    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;

    if (errors is String && errors.isNotEmpty) return errors;

    switch (statusCode) {
      case 400:
        return 'تعذّر إتمام الحجز، تحقّق من البيانات المدخلة';
      case 403:
        return 'لا تملك صلاحية إتمام هذا الحجز';
      case 404:
        return 'لم يتم العثور على المندوب أو المنتج المطلوب';
      case 500:
        return 'حدث خطأ في الخادم، حاول لاحقاً';
      default:
        return 'فشل إنشاء الحجز';
    }
  }

  Future<({bool success, String message, RepresentativeRequest? request})>
  updatePermissions({
    required String accessToken,
    required int requestId,
    required bool canList,
    required bool canNegotiate,
    required bool canCompleteSale,
    required double commissionPercentage,
  }) async {
    final response = await _client.patch(
      '/representatives/$requestId/update_permissions/',
      body: {
        'can_list': canList,
        'can_negotiate': canNegotiate,
        'can_complete_sale': canCompleteSale,
        'commission_percentage': commissionPercentage.toString(),
      },
    );

    return _parseActionResponse(
      response,
      successDefault: 'تمّ تحديث الصلاحيّات',
    );
  }
}
