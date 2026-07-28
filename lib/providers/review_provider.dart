import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/product_review.dart';
import '../services/review_service.dart';

class ReviewProvider extends ChangeNotifier {
  final int itemId;
  final _service = ReviewService();

  ReviewProvider(this.itemId);

  List<ProductReview> _reviews = [];
  ProductReview? _myReview;
  bool _myReviewChecked = false;
  bool _isLoadingReviews = false;
  bool _isLoadingMyReview = false;
  bool _isSubmitting = false;
  String? _error;

  List<ProductReview> get reviews => _reviews;
  ProductReview? get myReview => _myReview;
  bool get myReviewChecked => _myReviewChecked;
  bool get isLoadingReviews => _isLoadingReviews;
  bool get isLoadingMyReview => _isLoadingMyReview;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

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
      _reviews = await _service.fetchReviews(itemId: itemId);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingReviews = false;
      notifyListeners();
    }
  }

  Future<void> loadMyReview(String token) async {
    _isLoadingMyReview = true;
    notifyListeners();
    try {
      _myReview = await _service.fetchMyReview(itemId: itemId, token: token);
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
    XFile? image,
  }) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      final review = await _service.createReview(
        token: token,
        itemId: itemId,
        score: score,
        comment: comment,
        image: image,
      );
      _myReview = review;
      _reviews.insert(0, review);
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
    XFile? image,
  }) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      final updated = await _service.updateReview(
        token: token,
        reviewId: reviewId,
        score: score,
        comment: comment,
        image: image,
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
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
