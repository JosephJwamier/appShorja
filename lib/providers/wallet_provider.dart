import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  final WalletService _service = WalletService();

  Wallet? wallet;
  List<Deposit> deposits = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadAll({required String accessToken}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _service.fetchWallet(accessToken: accessToken),
        _service.fetchDeposits(accessToken: accessToken),
      ]);
      wallet = results[0] as Wallet;
      deposits = results[1] as List<Deposit>;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> deposit({
    required String accessToken,
    required String amount,
    required String cardLast4,
  }) async {
    try {
      final result = await _service.deposit(
        accessToken: accessToken,
        amount: amount,
        cardLast4: cardLast4,
      );
      wallet = result.wallet;
      deposits = [result.deposit, ...deposits];
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }
}
