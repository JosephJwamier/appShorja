import 'dart:convert';

import '../models/payment.dart';
import 'api_client.dart';

/// Talks to the backend's provider-agnostic payment endpoints.
///
/// Deliberately knows nothing about Al Qaseh, or any gateway. The app asks the
/// server which methods exist, opens whichever one the user picked, and polls
/// for the outcome. Adding a second gateway changes nothing on this side —
/// a new entry simply appears in [fetchMethods].
///
/// The app never touches card data: the server returns a hosted checkout URL
/// and the card is entered there, which is what keeps this project out of
/// PCI-DSS scope.
class PaymentService {
  final _client = ApiClient.instance;

  /// Payment methods the server can actually process right now. A gateway
  /// whose credentials are missing is not returned, so the picker can't offer
  /// something that would fail on tap.
  Future<List<PaymentMethod>> fetchMethods({required String accessToken}) async {
    final response = await _client.get('/payments/methods/');
    if (response.statusCode != 200) {
      throw Exception('تعذّر جلب طرق الدفع');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['data'] as List<dynamic>? ?? const []);
    return list
        .map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Opens a payment and returns it with a `checkoutUrl` to send the user to.
  Future<PaymentIntent> createPayment({
    required String accessToken,
    required String provider,
    required num amount,
  }) async {
    final response = await _client.post(
      '/payments/create/',
      body: {'provider': provider, 'amount': amount},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201) {
      throw Exception(_message(body, 'تعذّر بدء عملية الدفع'));
    }
    return PaymentIntent.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Current state of a payment. The server re-asks the gateway while the
  /// payment is still open, so this is authoritative — the `status` the
  /// browser came back with is not.
  Future<PaymentIntent> fetchPayment({
    required String accessToken,
    required String reference,
  }) async {
    final response = await _client.get('/payments/$reference/');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(_message(body, 'تعذّر جلب حالة العملية'));
    }
    return PaymentIntent.fromJson(body['data'] as Map<String, dynamic>);
  }

  String _message(Map<String, dynamic> body, String fallback) {
    final message = body['message'];
    return message is String && message.isNotEmpty ? message : fallback;
  }
}
