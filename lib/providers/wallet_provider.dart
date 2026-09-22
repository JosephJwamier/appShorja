import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  final WalletService _service = WalletService();

  Wallet? wallet;
  List<Deposit> deposits = [];
  WalletActivity? activity;
  bool isLoading = false;
  bool isSyncing = false;
  String? errorMessage;
  String? activityError;

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

  Future<void> loadActivity({required String accessToken}) async {
    activityError = null;
    try {
      activity = await _service.fetchActivity(accessToken: accessToken);
      // The activity payload carries the same three balances; keep the
      // balance card in step without a second round trip.
      final a = activity!;
      wallet = Wallet(
        balance: a.balance,
        heldBalance: a.heldBalance,
        availableBalance: a.availableBalance,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      activityError = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  /// The refresh arrow: re-asks the gateway about unfinished top-ups, then
  /// reloads everything. Returns the sync outcome for the snackbar, or null
  /// when the sync itself could not be reached (the reload still runs).
  Future<SyncResult?> refreshAll({required String accessToken}) async {
    if (isSyncing) return null;
    isSyncing = true;
    notifyListeners();
    SyncResult? result;
    try {
      result = await _service.syncPendingPayments(accessToken: accessToken);
    } catch (_) {
      result = null;
    }
    try {
      await Future.wait([
        loadAll(accessToken: accessToken),
        loadActivity(accessToken: accessToken),
      ]);
    } finally {
      isSyncing = false;
      notifyListeners();
    }
    return result;
  }
}
