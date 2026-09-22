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
}
extension WalletActivityApi on WalletService {
  Future<WalletActivity> fetchActivity({required String accessToken}) async {
    final response = await _client.get('/wallet/activity/');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return WalletActivity.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw Exception('فشل جلب حركة الأموال');
  }

  /// Re-asks the gateway about unfinished card top-ups. Manual on purpose —
  /// see payment_views.sync_pending_payments.
  Future<SyncResult> syncPendingPayments({required String accessToken}) async {
    final response = await _client.post('/payments/sync-pending/', body: const {});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SyncResult.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw Exception('تعذّرت المزامنة');
  }
}
