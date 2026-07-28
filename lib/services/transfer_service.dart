import 'dart:convert';
import '../models/resale_agreement.dart';
import 'api_client.dart';

typedef TransferActionResult = ({bool success, String message, ResaleAgreement? agreement});

class TransferService {
  final _client = ApiClient.instance;

  // token is kept for call-site compatibility — ApiClient tracks the live
  // token itself (and silently refreshes it on a 401).
  Future<({List<ResaleAgreement> items, int count})> _fetchList(
    String path,
    String token,
  ) async {
    final resp = await _client.get('/transfers/$path/');
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (body['data'] as List<dynamic>?) ?? [];
      final count = body['count'] as int? ?? list.length;
      return (
        items: list
            .map((e) => ResaleAgreement.fromJson(e as Map<String, dynamic>))
            .toList(),
        count: count,
      );
    }
    throw Exception('فشل جلب البيانات (${resp.statusCode})');
  }

  Future<({List<ResaleAgreement> items, int count})> fetchPendingApprovals({
    required String token,
  }) => _fetchList('pending_approvals', token);

  Future<({List<ResaleAgreement> items, int count})> fetchReceivedRequests({
    required String token,
  }) => _fetchList('received_requests', token);

  Future<({List<ResaleAgreement> items, int count})> fetchSentRequests({
    required String token,
  }) => _fetchList('sent_requests', token);

  Future<({List<ResaleAgreement> items, int count})> fetchMyAgreements({
    required String token,
  }) => _fetchList('my_agreements', token);

  Future<({List<ResaleAgreement> items, int count})> fetchItemsOnConsignment({
    required String token,
  }) => _fetchList('items_on_consignment', token);

  Future<({List<ResaleAgreement> items, int count})> fetchActive({
    required String token,
  }) => _fetchList('active', token);

  Future<({List<ResaleAgreement> items, int count})> fetchHistory({
    required String token,
  }) => _fetchList('history', token);

  ResaleAgreement? _extractAgreement(Map<String, dynamic> data) {
    if (data['data'] is Map) {
      return ResaleAgreement.fromJson(data['data'] as Map<String, dynamic>);
    }
    if (data.containsKey('id') && data.containsKey('status')) {
      return ResaleAgreement.fromJson(data);
    }
    return null;
  }

  Future<TransferActionResult> _action(
    String path,
    String token,
    Map<String, dynamic> body,
    String defaultSuccess,
  ) async {
    try {
      final resp = await _client.post(path, body: body);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final success = data['success'] as bool? ?? (resp.statusCode < 300);
      final message = data['message'] as String? ??
          (success
              ? defaultSuccess
              : _extractErrors(data['errors']) ?? 'فشلت العملية');
      final agreement = success ? _extractAgreement(data) : null;
      return (success: success, message: message, agreement: agreement);
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة', agreement: null);
    }
  }

  String? _extractErrors(dynamic errors) {
    if (errors is Map) {
      final messages = <String>[];
      for (final v in errors.values) {
        if (v is List) {
          messages.addAll(v.map((e) => e.toString()));
        } else if (v != null) {
          messages.add(v.toString());
        }
      }
      if (messages.isNotEmpty) return messages.join('\n');
    } else if (errors is List) {
      if (errors.isNotEmpty) return errors.map((e) => e.toString()).join('\n');
    } else if (errors is String) {
      return errors;
    }
    return null;
  }

  Future<TransferActionResult> createAgreement(
    CreateTransferRequest request, {
    required String token,
  }) => _action(
    '/transfers/create_agreement/',
    token,
    request.toJson(),
    'تمّ إرسال طلب نقل الملكية',
  );

  Future<TransferActionResult> approve({required String token, required int id}) =>
      _action('/transfers/$id/approve/', token, {}, 'تمّت الموافقة ونقل الملكية');

  Future<TransferActionResult> reject({
    required String token,
    required int id,
    String? reason,
  }) => _action(
    '/transfers/$id/reject/',
    token,
    reason != null && reason.isNotEmpty ? {'rejection_reason': reason} : {},
    'تمّ الرفض',
  );

  Future<TransferActionResult> cancel({required String token, required int id}) =>
      _action('/transfers/$id/cancel/', token, {}, 'تمّ الإلغاء');

  Future<TransferActionResult> complete({required String token, required int id}) =>
      _action('/transfers/$id/complete/', token, {}, 'تمّ إنهاء الاتفاقية');
}
