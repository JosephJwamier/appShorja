import 'package:flutter/material.dart';
import '../models/listing.dart';
import '../services/item_service.dart';

/// Infinite-scroll pagination for the "عرض الكل" recommended-listings screen.
/// Same reset/loadMore/generation-guard shape as [HomeItemsProvider] — kept
/// as a separate, simpler provider since this feed has no filters/search.
class RecommendedListingsProvider extends ChangeNotifier {
  final ItemService _service = ItemService();

  List<FixedListing> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _errorMessage;

  // Incremented on every reset() call so in-flight page loads from
  // previous generations are silently discarded when they arrive.
  int _generation = 0;

  List<FixedListing> get items => _items;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => !_isLoading && _items.isEmpty && _errorMessage == null;

  Future<void> reset({required String accessToken}) async {
    _items = [];
    _page = 1;
    _hasMore = true;
    _errorMessage = null;
    _isLoadingMore = false;

    final gen = ++_generation;

    _isLoading = true;
    notifyListeners();

    await _loadPage(accessToken: accessToken, page: 1, gen: gen);
  }

  Future<void> loadMore({required String accessToken}) async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    _isLoadingMore = true;
    notifyListeners();

    final gen = _generation;
    try {
      await _loadPage(accessToken: accessToken, page: _page + 1, gen: gen);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _loadPage({
    required String accessToken,
    required int page,
    required int gen,
  }) async {
    try {
      final result = await _service.fetchRecommendedListingsPaginated(
        accessToken: accessToken,
        page: page,
      );

      if (gen != _generation) return;

      if (page == 1) {
        _items = result.listings;
      } else {
        _items = [..._items, ...result.listings];
        _page = page;
      }
      _hasMore = result.hasMore;
    } catch (e) {
      if (gen != _generation) return;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (gen == _generation && page == 1) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }
}
