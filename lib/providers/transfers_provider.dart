import 'package:flutter/material.dart';
import '../models/resale_agreement.dart';
import '../services/transfer_service.dart';

enum TransferTab { received, sent, active, history }

class TabState {
  List<ResaleAgreement> items = [];
  bool isLoading = false;
  String? error;

  bool get isEmpty => !isLoading && items.isEmpty && error == null;
}

class TransfersProvider extends ChangeNotifier {
  final _service = TransferService();

  final _states = {for (final t in TransferTab.values) t: TabState()};

  TabState stateOf(TransferTab tab) => _states[tab]!;

  /// Resale agreements sent to this user (as item owner) still awaiting
  /// their approve/reject decision — drives the "incoming requests" badge.
  int get pendingReceivedCount =>
      _states[TransferTab.received]!.items.where((a) => a.isPending).length;

  Future<void> loadTab(TransferTab tab, {required String token}) async {
    final s = _states[tab]!;
    if (s.isLoading) return;

    s.isLoading = true;
    notifyListeners();

    try {
      final result = await _fetchFor(tab, token: token);
      s.items = result.items;
      s.error = null;
    } catch (e) {
      s.error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      s.isLoading = false;
      notifyListeners();
    }
  }

  Future<({List<ResaleAgreement> items, int count})> _fetchFor(
    TransferTab tab, {
    required String token,
  }) => switch (tab) {
    TransferTab.received => _service.fetchReceivedRequests(token: token),
    TransferTab.sent => _service.fetchSentRequests(token: token),
    TransferTab.active => _service.fetchActive(token: token),
    TransferTab.history => _service.fetchHistory(token: token),
  };

  void _sync(ResaleAgreement updated) {
    for (final s in _states.values) {
      final i = s.items.indexWhere((a) => a.id == updated.id);
      if (i != -1) s.items[i] = updated;
    }
  }

  Future<({bool success, String message})> createAgreement({
    required String token,
    required int itemId,
    int quantity = 1,
    String storageFeeType = 'none',
    double? storageFeeAmount,
    int storageFeePeriodDays = 30,
    int? durationDays,
    String requestMessage = '',
    String notes = '',
  }) async {
    final r = await _service.createAgreement(
      CreateTransferRequest(
        itemId: itemId,
        quantity: quantity,
        storageFeeType: storageFeeType,
        storageFeeAmount: storageFeeAmount,
        storageFeePeriodDays: storageFeePeriodDays,
        durationDays: durationDays,
        requestMessage: requestMessage,
        notes: notes,
      ),
      token: token,
    );
    return (success: r.success, message: r.message);
  }

  Future<({bool success, String message})> approve({
    required String token,
    required int id,
  }) async {
    final r = await _service.approve(token: token, id: id);
    if (r.success && r.agreement != null) _sync(r.agreement!);
    notifyListeners();
    return (success: r.success, message: r.message);
  }

  Future<({bool success, String message})> reject({
    required String token,
    required int id,
    String? reason,
  }) async {
    final r = await _service.reject(token: token, id: id, reason: reason);
    if (r.success && r.agreement != null) _sync(r.agreement!);
    notifyListeners();
    return (success: r.success, message: r.message);
  }

  Future<({bool success, String message})> cancel({
    required String token,
    required int id,
  }) async {
    final r = await _service.cancel(token: token, id: id);
    if (r.success && r.agreement != null) _sync(r.agreement!);
    notifyListeners();
    return (success: r.success, message: r.message);
  }

  Future<({bool success, String message})> complete({
    required String token,
    required int id,
  }) async {
    final r = await _service.complete(token: token, id: id);
    if (r.success && r.agreement != null) _sync(r.agreement!);
    notifyListeners();
    return (success: r.success, message: r.message);
  }
}
