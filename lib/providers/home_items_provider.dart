import 'package:flutter/material.dart';
import '../models/filter_params.dart';
import '../models/listing.dart';
import '../services/item_service.dart';

class HomeItemsProvider extends ChangeNotifier {
  final ItemService _service = ItemService();

  List<FixedListing> _items = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _errorMessage;
  FilterParams _filters = FilterParams.empty;
  String _searchQuery = '';

  // Incremented on every reset() call so in-flight page loads from
  // previous generations are silently discarded when they arrive.
  int _generation = 0;

  List<FixedListing> get items => _items;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => !_isLoading && _items.isEmpty && _errorMessage == null;
  FilterParams get filters => _filters;

  /// Applies [filters] and reloads from page 1.
  /// Pass [categoryId] alone to do a quick category-only reset (clears other filters).
  /// Call with no optional args to refresh with the existing filters.
  Future<void> reset({
    required String accessToken,
    FilterParams? filters,
    int? categoryId,
    bool isCategoryReset = false,
    String search = '',
  }) async {
    if (filters != null) {
      _filters = filters;
    } else if (isCategoryReset) {
      _filters = FilterParams(categoryId: categoryId);
    }
    // else: keep existing filters (refresh behaviour)

    _searchQuery = search;
    _items = [];
    _page = 1;
    _hasMore = true;
    _errorMessage = null;
    _isLoadingMore = false;

    // New generation: any in-flight request from a previous reset() is obsolete.
    final gen = ++_generation;

    _isLoading = true;
    notifyListeners(); // show spinner immediately

    await _loadPage(accessToken: accessToken, page: 1, gen: gen);
  }

  Future<void> loadMore({required String accessToken}) async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    _isLoadingMore = true;
    notifyListeners();

    final gen = _generation; // capture current generation
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
      final result = await _service.fetchFixedListingsPaginated(
        accessToken: accessToken,
        page: page,
        filters: _filters,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      // Discard if a newer reset() was called while this was in flight.
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
