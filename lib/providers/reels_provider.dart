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

  // ريلزات متجر واحد — شبكة صفحته العامة كما يراها الزائر.
  //
  // قائمة ثالثة مستقلّة، لا إعادة استخدام لـ_reels: الزائر يفتح صفحة
  // المتجر من داخل الخلاصة نفسها (بالنقر على اسم المتجر فوق الريل)، فلو
  // كتبنا ريلزات المتجر فوق الخلاصة لوجدها فارغةً — أو فيها متجر واحد —
  // لحظة رجوعه إليها.
  List<Reel> _storeReels = [];
  int? _storeReelsStoreId;
  bool _isLoadingStoreReels = false;
  bool _isLoadingMoreStoreReels = false;
  String? _storeReelsError;
  int _storeReelsPage = 1;
  bool _storeReelsHasMore = false;

  List<Reel> get storeReels => _storeReels;

  /// أيّ متجر تخصّ [storeReels] الآن — شاشة المتجر تقرأه لتتأكّد أن ما
  /// تعرضه يخصّها هي، لا متجراً فُتح قبلها وما زالت قائمته محمّلة.
  int? get storeReelsStoreId => _storeReelsStoreId;
  bool get isLoadingStoreReels => _isLoadingStoreReels;
  bool get isLoadingMoreStoreReels => _isLoadingMoreStoreReels;
  String? get storeReelsError => _storeReelsError;
  bool get storeReelsHasMore => _storeReelsHasMore;

  // الريلز المحفوظة — مفضلة المشاهد.
  //
  // قائمة رابعة لنفس سبب القائمة الثالثة: شاشة المفضلة تُفتح من تبويب
  // الحساب فوق الخلاصة، والعارض الذي يُدفع منها يشارك القائمة مع الشبكة
  // تحته — فإلغاء الحفظ داخل العارض يُخرج البلاطة من الشبكة بلا إعادة جلب.
  List<Reel> _savedReels = [];
  bool _isLoadingSavedReels = false;
  bool _isLoadingMoreSavedReels = false;
  String? _savedReelsError;
  int _savedReelsPage = 1;
  bool _savedReelsHasMore = false;

  List<Reel> get savedReels => _savedReels;
  bool get isLoadingSavedReels => _isLoadingSavedReels;
  bool get isLoadingMoreSavedReels => _isLoadingMoreSavedReels;
  String? get savedReelsError => _savedReelsError;
  bool get savedReelsHasMore => _savedReelsHasMore;

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

  /// يطبّق تعديلاً على الريل أينما كان في القوائم الأربع.
  ///
  /// الريل الواحد قد يكون في أربعتها معاً: صاحب متجر يتصفّح الخلاصة، فيرى
  /// ريله فيها وفي «ريلزاتي» وفي شبكة صفحة متجره — وقد يكون حفظه فهو في
  /// المفضلة أيضاً. ترقيع واحدة دون أخرى يعني رقمين مختلفين للشيء نفسه على
  /// شاشتين متجاورتين.
  bool _patchEverywhere(int reelId, Reel Function(Reel) transform) {
    var changed = false;
    for (final list in [_reels, _myReels, _storeReels, _savedReels]) {
      final index = list.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        list[index] = transform(list[index]);
        changed = true;
      }
    }
    return changed;
  }

  /// Optimistic local toggle so the feed's like button feels instant; the
  /// actual REST call happens from the feed screen.
  void applyLikeUpdate(int reelId, bool isLiked, int likesCount) {
    if (_patchEverywhere(
        reelId, (r) => r.copyWith(isLikedByMe: isLiked, likesCount: likesCount))) {
      notifyListeners();
    }
  }

  /// نظير [applyLikeUpdate] للعلم الخاصّ، بلا عدّاد — فالحفظ لا رقم له.
  ///
  /// وإلغاء الحفظ يُخرج الريل من قائمة المحفوظة لا يُرقّعه فيها: تلك
  /// القائمة *هي* المفضلة، وريلٌ غير محفوظ باقٍ فيها إلى التحديث القادم
  /// يُقرأ كعطب. أمّا في القوائم الثلاث الأخرى فالعلم يُرقّع في مكانه،
  /// فالريل ما زال ينتمي إليها.
  void applySaveUpdate(int reelId, bool isSaved) {
    var changed = _patchEverywhere(reelId, (r) => r.copyWith(isSavedByMe: isSaved));
    if (!isSaved) {
      final before = _savedReels.length;
      _savedReels.removeWhere((r) => r.id == reelId);
      changed = changed || _savedReels.length != before;
    }
    if (changed) notifyListeners();
  }

  /// Bumps the visible comment counter right after a successful post —
  /// avoids a full reel refetch just to keep the overlay's count in sync.
  void applyCommentPosted(int reelId) {
    if (_patchEverywhere(
        reelId, (r) => r.copyWith(commentsCount: r.commentsCount + 1))) {
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
  /// swaps the reel wherever it is listed so an open feed or grid reflects
  /// the change without a refetch that would reset the scroll position.
  void applyReelUpdate(Reel updated) {
    if (_patchEverywhere(updated.id, (_) => updated)) notifyListeners();
  }

  /// Called after a successful permanent delete — removes it from every
  /// list locally instead of a full refetch.
  void removeReelLocally(int reelId) {
    _reels.removeWhere((r) => r.id == reelId);
    _myReels.removeWhere((r) => r.id == reelId);
    _storeReels.removeWhere((r) => r.id == reelId);
    _savedReels.removeWhere((r) => r.id == reelId);
    notifyListeners();
  }

  // ---- ريلزات متجر واحد ---------------------------------------------------

  /// يحمّل الصفحة الأولى من ريلزات [storeId].
  ///
  /// يبدّل القائمة كاملةً لا يضيف إليها: فتح متجرٍ ثانٍ يعني شبكةً أخرى،
  /// ودمجهما كان سيعرض ريلزات متجر في صفحة غيره.
  Future<void> loadStoreReels({
    required String accessToken,
    required int storeId,
  }) async {
    _isLoadingStoreReels = true;
    _storeReelsError = null;
    _storeReelsStoreId = storeId;
    _storeReelsPage = 1;
    notifyListeners();

    try {
      final result = await _service.fetchStoreReels(
          accessToken: accessToken, storeId: storeId);
      // المتجر قد يكون تبدّل أثناء الطلب (رجوع ثم فتح متجر آخر بسرعة) —
      // استجابةٌ متأخّرة لمتجرٍ غادره المستخدم لا تُكتب فوق الحالي.
      if (_storeReelsStoreId != storeId) return;
      _storeReels = result.reels;
      _storeReelsHasMore = result.hasMore;
    } catch (e) {
      if (_storeReelsStoreId != storeId) return;
      _storeReels = [];
      _storeReelsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingStoreReels = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreStoreReels({required String accessToken}) async {
    final storeId = _storeReelsStoreId;
    if (storeId == null || _isLoadingMoreStoreReels || !_storeReelsHasMore) {
      return;
    }
    _isLoadingMoreStoreReels = true;
    notifyListeners();

    try {
      final result = await _service.fetchStoreReels(
          accessToken: accessToken, storeId: storeId, page: _storeReelsPage + 1);
      if (_storeReelsStoreId != storeId) return;
      _storeReelsPage++;
      _storeReels = [..._storeReels, ...result.reels];
      _storeReelsHasMore = result.hasMore;
    } catch (_) {
      // silent fail — existing data stays visible, same as loadMore
    } finally {
      _isLoadingMoreStoreReels = false;
      notifyListeners();
    }
  }

  /// تُستدعى عند مغادرة صفحة متجر، فلا تُعرض شبكتُه لمتجرٍ يُفتح بعده قبل
  /// أن يصل ردُّ طلبه.
  void clearStoreReels() {
    if (_storeReels.isEmpty && _storeReelsStoreId == null) return;
    _storeReels = [];
    _storeReelsStoreId = null;
    _storeReelsError = null;
    _storeReelsHasMore = false;
    _storeReelsPage = 1;
    notifyListeners();
  }

  // ---- الريلز المحفوظة ----------------------------------------------------

  Future<void> loadSavedReels({required String accessToken}) async {
    _isLoadingSavedReels = true;
    _savedReelsError = null;
    _savedReelsPage = 1;
    notifyListeners();

    try {
      final result = await _service.fetchSavedReels(accessToken: accessToken);
      _savedReels = result.reels;
      _savedReelsHasMore = result.hasMore;
    } catch (e) {
      _savedReels = [];
      _savedReelsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingSavedReels = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreSavedReels({required String accessToken}) async {
    if (_isLoadingMoreSavedReels || !_savedReelsHasMore) return;
    _isLoadingMoreSavedReels = true;
    notifyListeners();

    try {
      final result = await _service.fetchSavedReels(
          accessToken: accessToken, page: _savedReelsPage + 1);
      _savedReelsPage++;
      _savedReels = [..._savedReels, ...result.reels];
      _savedReelsHasMore = result.hasMore;
    } catch (_) {
      // silent fail — existing data stays visible, same as loadMore
    } finally {
      _isLoadingMoreSavedReels = false;
      notifyListeners();
    }
  }

  /// Prepends a freshly-published reel (from create_reel_screen) so it's
  /// visible immediately without waiting on the next feed refresh.
  void prependPublishedReel(Reel reel) {
    _reels = [reel, ..._reels];
    _myReels = [reel, ..._myReels];
    notifyListeners();
  }
}
