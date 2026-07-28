import 'package:flutter/material.dart';
import '../models/representative_request.dart';
import '../services/representative_service.dart';

class RepresentativeRequestsProvider extends ChangeNotifier {
  final RepresentativeService _service = RepresentativeService();

  List<RepresentativeRequest> _received = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RepresentativeRequest> get received => _received;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get pendingReceivedCount => _received.where((r) => r.isPending).length;

  Future<void> loadReceivedRequests({required String accessToken}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _received = await _service.fetchReceivedRequests(
        accessToken: accessToken,
      );
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<({bool success, String message})> acceptRequest({
    required String accessToken,
    required int requestId,
  }) async {
    final result = await _service.acceptRequest(
      accessToken: accessToken,
      requestId: requestId,
    );

    if (result.success && result.request != null) {
      final index = _received.indexWhere((r) => r.id == requestId);
      if (index != -1) {
        _received[index] = result.request!;
        notifyListeners();
      }
    }

    return (success: result.success, message: result.message);
  }

  Future<({bool success, String message})> rejectRequest({
    required String accessToken,
    required int requestId,
    required String rejectionReason,
  }) async {
    final result = await _service.rejectRequest(
      accessToken: accessToken,
      requestId: requestId,
      rejectionReason: rejectionReason,
    );

    if (result.success && result.request != null) {
      final index = _received.indexWhere((r) => r.id == requestId);
      if (index != -1) {
        _received[index] = result.request!;
        notifyListeners();
      }
    }

    return (success: result.success, message: result.message);
  }

  List<RepresentativeRequest> _active = [];
  bool _isLoadingActive = false;
  String? _errorActive;

  List<RepresentativeRequest> get active => _active;
  bool get isLoadingActive => _isLoadingActive;
  String? get errorActive => _errorActive;

  List<RepresentativeRequest> _sent = [];
  bool _isLoadingSent = false;
  String? _errorSent;

  List<RepresentativeRequest> get sent => _sent;
  bool get isLoadingSent => _isLoadingSent;
  String? get errorSent => _errorSent;

  Future<void> loadActiveRepresentatives({required String accessToken}) async {
    _isLoadingActive = true;
    _errorActive = null;
    notifyListeners();

    try {
      _active = await _service.fetchActiveRepresentatives(
        accessToken: accessToken,
      );
    } catch (e) {
      _errorActive = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingActive = false;
      notifyListeners();
    }
  }

  Future<void> loadSentRequests({required String accessToken}) async {
    _isLoadingSent = true;
    _errorSent = null;
    notifyListeners();

    try {
      _sent = await _service.fetchSentRequests(accessToken: accessToken);
    } catch (e) {
      _errorSent = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingSent = false;
      notifyListeners();
    }
  }

  Future<({bool success, String message})> cancelRequest({
    required String accessToken,
    required int requestId,
  }) async {
    final result = await _service.cancelRequest(
      accessToken: accessToken,
      requestId: requestId,
    );

    if (result.success && result.request != null) {
      final updated = result.request!;

      // تحديث في قائمة المرسلة (إن كان الطلب فيها)
      final sentIndex = _sent.indexWhere((r) => r.id == requestId);
      if (sentIndex != -1) _sent[sentIndex] = updated;

      // تحديث في قائمة المستلمة (للاتساق)
      final receivedIndex = _received.indexWhere((r) => r.id == requestId);
      if (receivedIndex != -1) _received[receivedIndex] = updated;

      // إزالة من قائمة النشطة (لأنّ الملغاة لم تعد نشطة)
      _active.removeWhere((r) => r.id == requestId);

      notifyListeners();
    }

    return (success: result.success, message: result.message);
  }

  Future<({bool success, String message})> deleteRequest({
    required String accessToken,
    required int requestId,
  }) async {
    try {
      final success = await _service.deleteRequest(
        accessToken: accessToken,
        requestId: requestId,
      );

      if (success) {
        _sent.removeWhere((r) => r.id == requestId);
        _received.removeWhere((r) => r.id == requestId);
        _active.removeWhere((r) => r.id == requestId);
        notifyListeners();
        return (success: true, message: 'تمّ الحذف');
      }
      return (success: false, message: 'فشل الحذف');
    } catch (e) {
      return (
        success: false,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<({bool success, String message})> updatePermissions({
    required String accessToken,
    required int requestId,
    required bool canList,
    required bool canNegotiate,
    required bool canCompleteSale,
    required double commissionPercentage,
  }) async {
    final result = await _service.updatePermissions(
      accessToken: accessToken,
      requestId: requestId,
      canList: canList,
      canNegotiate: canNegotiate,
      canCompleteSale: canCompleteSale,
      commissionPercentage: commissionPercentage,
    );

    if (result.success && result.request != null) {
      final updated = result.request!;
      final lists = [_received, _sent, _active];
      for (final list in lists) {
        final index = list.indexWhere((r) => r.id == requestId);
        if (index != -1) {
          list[index] = updated;
        }
      }
      notifyListeners();
    }

    return (success: result.success, message: result.message);
  }
}
