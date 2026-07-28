import 'package:flutter/material.dart';
import '../models/store_review.dart';
import '../services/store_review_service.dart';

class StoreReviewProvider extends ChangeNotifier {
  final int storeId;
  final _service = StoreReviewService();

  StoreReviewProvider(this.storeId);

  List<StoreReview> _reviews = [];
  StoreReview? _myReview;
  bool _myReviewChecked = false;
  bool _isLoadingReviews = false;
  bool _isLoadingMore = false;
  bool _isLoadingMyReview = false;
  bool _isSubmitting = false;
  String? _error;
  String? _nextPageUrl;
  int _totalCount = 0;

  List<StoreReview> get reviews => _reviews;
  StoreReview? get myReview => _myReview;
  bool get myReviewChecked => _myReviewChecked;
  bool get isLoadingReviews => _isLoadingReviews;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoadingMyReview => _isLoadingMyReview;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  bool get hasMore => _nextPageUrl != null;
  int get totalCount => _totalCount;

  /// Count per star (1–5) from the currently loaded reviews.
  Map<int, int> get scoreBreakdown {
    final map = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _reviews) {
      map[r.score] = (map[r.score] ?? 0) + 1;
    }
    return map;
  }

  Future<void> loadReviews() async {
    _isLoadingReviews = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.fetchReviews(storeId: storeId);
      _reviews = page.results;
      _nextPageUrl = page.next;
      _totalCount = page.count;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingReviews = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || _nextPageUrl == null) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _service.fetchReviews(
        storeId: storeId,
        pageUrl: _nextPageUrl,
      );
      _reviews.addAll(page.results);
      _nextPageUrl = page.next;
      _totalCount = page.count;
    } catch (_) {
      // تجاهل فشل تحميل الصفحة التالية؛ يمكن للمستخدم إعادة المحاولة بالتمرير
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> loadMyReview(String token) async {
    _isLoadingMyReview = true;
    notifyListeners();
    try {
      _myReview = await _service.fetchMyReview(storeId: storeId, token: token);
    } catch (_) {
      _myReview = null;
    } finally {
      _myReviewChecked = true;
      _isLoadingMyReview = false;
      notifyListeners();
    }
  }

  Future<void> createReview({
    required String token,
    required int score,
    String? comment,
  }) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      final review = await _service.createReview(
        token: token,
        storeId: storeId,
        score: score,
        comment: comment,
      );
      _myReview = review;
      _reviews.insert(0, review);
      _totalCount += 1;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> updateReview({
    required String token,
    required int reviewId,
    int? score,
    String? comment,
  }) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      final updated = await _service.updateReview(
        token: token,
        reviewId: reviewId,
        score: score,
        comment: comment,
      );
      _myReview = updated;
      final idx = _reviews.indexWhere((r) => r.id == reviewId);
      if (idx != -1) _reviews[idx] = updated;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> deleteReview({
    required String token,
    required int reviewId,
  }) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      await _service.deleteReview(token: token, reviewId: reviewId);
      _myReview = null;
      _reviews.removeWhere((r) => r.id == reviewId);
      _totalCount = _totalCount > 0 ? _totalCount - 1 : 0;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
