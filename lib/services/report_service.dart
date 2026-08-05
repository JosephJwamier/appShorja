import 'dart:convert';
import 'api_client.dart';

class ReportService {
  final _client = ApiClient.instance;

  Future<({bool success, String message})> createReport({
    required String accessToken,
    required String targetType, // 'item' | 'store' | 'user'
    required int targetId,
    required String reason,
    String description = '',
  }) async {
    final response = await _client.post(
      '/reports/create_report/',
      body: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'description': description,
      },
    );
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ?? false;
      final errors = body['errors'];
      final message = body['message'] as String? ??
          (success ? 'تم إرسال البلاغ' : 'فشل إرسال البلاغ');
      return (
        success: success,
        message: !success && errors != null ? errors.toString() : message,
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }
}
