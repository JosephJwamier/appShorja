import 'dart:convert';
import '../models/dispute.dart';
import 'api_client.dart';

class DisputeService {
  final _client = ApiClient.instance;

  /// نزاعاتي — كل النزاعات التي أنا طرف فيها (شاكياً أو مشكواً بحقّي)
  Future<List<Dispute>> fetchMyDisputes({required String accessToken}) async {
    final response = await _client.get('/disputes/');
    if (response.statusCode != 200) {
      throw Exception('فشل جلب النزاعات');
    }
    final body = jsonDecode(response.body);
    final results = body is Map<String, dynamic>
        ? (body['results'] as List<dynamic>? ?? [])
        : (body as List<dynamic>);
    return results
        .cast<Map<String, dynamic>>()
        .map((e) => Dispute.fromJson(e))
        .toList();
  }

  Future<({bool success, String message, Dispute? dispute})> createDispute({
    required String accessToken,
    required int itemId,
    int? reservationId,
    required String title,
    required String description,
    String reason = '',
  }) async {
    final response = await _client.post(
      '/disputes/create_dispute/',
      body: {
        'item_id': itemId,
        'reservation_id': ?reservationId,
        'title': title,
        'description': description,
        'reason': reason,
      },
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ?? false;
      if (!success) {
        final errors = body['errors'];
        final message = body['message'] as String? ?? 'فشل إرسال النزاع';
        return (
          success: false,
          message: errors != null ? errors.toString() : message,
          dispute: null,
        );
      }
      final data = body['data'] as Map<String, dynamic>?;
      return (
        success: true,
        message: body['message'] as String? ?? 'تم إرسال النزاع',
        dispute: data != null ? Dispute.fromJson(data) : null,
      );
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        dispute: null,
      );
    }
  }
}
