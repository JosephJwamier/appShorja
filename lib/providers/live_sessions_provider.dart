import 'package:flutter/material.dart';
import '../models/live_session.dart';
import '../services/live_session_service.dart';

class LiveSessionsProvider extends ChangeNotifier {
  final LiveSessionService _service = LiveSessionService();

  List<LiveSession> _sessions = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  bool _hasMore = false;
  String _ordering = '-current_viewer_count';

  List<LiveSession> get sessions => _sessions;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  String get ordering => _ordering;

  Future<void> loadSessions({
    required String accessToken,
    String? ordering,
    String? status = 'live',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _currentPage = 1;
    if (ordering != null) _ordering = ordering;
    notifyListeners();

    try {
      final result = await _service.fetchLiveSessions(
        accessToken: accessToken,
        ordering: _ordering,
        status: status,
        page: 1,
      );
      _sessions = result.sessions;
      _hasMore = result.hasMore;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore({required String accessToken, String? status = 'live'}) async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _service.fetchLiveSessions(
        accessToken: accessToken,
        ordering: _ordering,
        status: status,
        page: _currentPage + 1,
      );
      _currentPage++;
      _sessions = [..._sessions, ...result.sessions];
      _hasMore = result.hasMore;
    } catch (_) {
      // silent fail — existing data stays visible
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Optimistic local toggle so the discovery grid's like button feels
  /// instant; the actual REST call happens from the viewer/card widget.
  void applyLikeUpdate(int sessionId, bool isLiked, int likesCount) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;
    _sessions[index] = _sessions[index].copyWith(
      isLikedByMe: isLiked,
      likesCount: likesCount,
    );
    notifyListeners();
  }
}
