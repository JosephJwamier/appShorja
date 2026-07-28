import 'dart:convert';
import '../models/wallet.dart';
import 'api_client.dart';

class WalletService {
  final _client = ApiClient.instance;

  // accessToken is kept for call-site compatibility — ApiClient tracks the
  // live token itself (and silently refreshes it on a 401), so it's no
  // longer read directly here.
  Future<Wallet> fetchWallet({required String accessToken}) async {
    final response = await _client.get('/wallet/me/');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Wallet.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw Exception('فشل جلب بيانات المحفظة');
  }

  Future<List<Deposit>> fetchDeposits({required String accessToken}) async {
    final response = await _client.get('/wallet/my_deposits/');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>;
      return list.map((d) => Deposit.fromJson(d as Map<String, dynamic>)).toList();
    }
    throw Exception('فشل جلب سجل الإيداعات');
  }

  Future<({Wallet wallet, Deposit deposit})> deposit({
    required String accessToken,
    required String amount,
    required String cardLast4,
  }) async {
    final response = await _client.post(
      '/wallet/deposit/',
      body: {'amount': amount, 'card_last4': cardLast4},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      final d = body['data'] as Map<String, dynamic>;
      return (
        wallet: Wallet.fromJson(d['wallet'] as Map<String, dynamic>),
        deposit: Deposit.fromJson(d['deposit'] as Map<String, dynamic>),
      );
    }
    throw Exception(body['message'] ?? 'فشل الإيداع');
  }
}
