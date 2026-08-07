import 'package:flutter/material.dart';
import '../models/reel.dart';
import '../services/reel_service.dart';

/// Feed + owner-management state for Reels. Mirrors LiveSessionsProvider
/// (lib/providers/live_sessions_provider.dart) for the pagination and
/// optimistic-like-update pattern, and additionally tracks the current
/// store's own reels (for the my-reels management screen) in the same
/// provider rather than a second one, since both share the exact same
/// like/comment optimistic-update needs.
class ReelsProvider extends ChangeNotifier {
  final ReelService _service = ReelService();

  List<Reel> _reels = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  bool _hasMore = false;

  List<Reel> get reels => _reels;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;

  List<Reel> _myReels = [];
  bool _isLoadingMyReels = false;
  String? _myReelsError;

  List<Reel> get myReels => _myReels;
  bool get isLoadingMyReels => _isLoadingMyReels;
  String? get myReelsError => _myReelsError;

  Future<void> loadFeed({required String accessToken}) async {
    _isLoading = true;
    _errorMessage = null;
    _currentPage = 1;
    notifyListeners();

    try {
      final result = await _service.fetchFeed(accessToken: accessToken, page: 1);
      _reels = result.reels;
      _hasMore = result.hasMore;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore({required String accessToken}) async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final result =
          await _service.fetchFeed(accessToken: accessToken, page: _currentPage + 1);
      _currentPage++;
      _reels = [..._reels, ...result.reels];
      _hasMore = result.hasMore;
    } catch (_) {
      // silent fail — existing data stays visible
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Optimistic local toggle so the feed's like button feels instant; the
  /// actual REST call happens from the feed screen. Patches both lists
  /// since the same reel can appear in the public feed and in "my reels".
  void applyLikeUpdate(int reelId, bool isLiked, int likesCount) {
    var changed = false;
    final index = _reels.indexWhere((r) => r.id == reelId);
    if (index != -1) {
      _reels[index] = _reels[index].copyWith(isLikedByMe: isLiked, likesCount: likesCount);
      changed = true;
    }
    final myIndex = _myReels.indexWhere((r) => r.id == reelId);
    if (myIndex != -1) {
      _myReels[myIndex] =
          _myReels[myIndex].copyWith(isLikedByMe: isLiked, likesCount: likesCount);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Bumps the visible comment counter right after a successful post —
  /// avoids a full reel refetch just to keep the overlay's count in sync.
  void applyCommentPosted(int reelId) {
    final index = _reels.indexWhere((r) => r.id == reelId);
    if (index != -1) {
      _reels[index] =
          _reels[index].copyWith(commentsCount: _reels[index].commentsCount + 1);
      notifyListeners();
    }
  }

  Future<void> loadMyReels({required String accessToken}) async {
    _isLoadingMyReels = true;
    _myReelsError = null;
    notifyListeners();

    try {
      _myReels = await _service.fetchMyReels(accessToken: accessToken);
    } catch (e) {
      _myReelsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingMyReels = false;
      notifyListeners();
    }
  }

  /// Called after a successful owner edit (caption / tagged product) —
  /// swaps the reel in both lists so the open feed reflects the change
  /// without a refetch that would reset the viewer's scroll position.
  void applyReelUpdate(Reel updated) {
    var changed = false;
    final index = _reels.indexWhere((r) => r.id == updated.id);
    if (index != -1) {
      _reels[index] = updated;
      changed = true;
    }
    final myIndex = _myReels.indexWhere((r) => r.id == updated.id);
    if (myIndex != -1) {
      _myReels[myIndex] = updated;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Called after a successful permanent delete — removes it from both lists
  /// locally instead of a full refetch.
  void removeReelLocally(int reelId) {
    _reels.removeWhere((r) => r.id == reelId);
    _myReels.removeWhere((r) => r.id == reelId);
    notifyListeners();
  }

  /// Prepends a freshly-published reel (from create_reel_screen) so it's
  /// visible immediately without waiting on the next feed refresh.
  void prependPublishedReel(Reel reel) {
    _reels = [reel, ..._reels];
    _myReels = [reel, ..._myReels];
    notifyListeners();
  }
}
