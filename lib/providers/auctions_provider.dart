import 'package:flutter/material.dart';
import '../models/auction.dart';
import '../models/filter_params.dart';
import '../services/auction_service.dart';

class AuctionsProvider extends ChangeNotifier {
  final AuctionService _auctionService = AuctionService();

  List<Auction> _auctions = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _currentPage = 1;
  bool _hasMore = false;

  String _searchQuery = '';
  String? _status;
  bool _activeOnly = false;
  FilterParams _filters = FilterParams.empty;

  List<Auction> get auctions => _auctions;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  FilterParams get filters => _filters;
  String? get status => _status;

  Future<void> loadAuctions({
    required String accessToken,
    String? search,
    String? status,
    bool activeOnly = false,
    FilterParams? filters,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _currentPage = 1;
    _searchQuery = search ?? '';
    _status = status;
    _activeOnly = activeOnly;
    if (filters != null) _filters = filters;
    notifyListeners();

    try {
      final result = await _auctionService.fetchAuctions(
        accessToken: accessToken,
        page: 1,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        status: _status,
        activeOnly: _activeOnly,
        filters: _filters,
      );
      _auctions = result.auctions;
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
      final result = await _auctionService.fetchAuctions(
        accessToken: accessToken,
        page: _currentPage + 1,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        status: _status,
        activeOnly: _activeOnly,
        filters: _filters,
      );
      _currentPage++;
      _auctions = [..._auctions, ...result.auctions];
      _hasMore = result.hasMore;
    } catch (_) {
      // silent fail — existing data stays visible
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }
}
