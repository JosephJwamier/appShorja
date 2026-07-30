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
  DateTime? _endsBefore;
  FilterParams _filters = FilterParams.empty;

  // Incremented on every loadAuctions() call so a page load superseded by a
  // newer filter/search change is silently discarded when it arrives late.
  int _generation = 0;

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
    DateTime? endsBefore,
    FilterParams? filters,
  }) async {
    _isLoading = true;
    _isLoadingMore = false;
    _errorMessage = null;
    _currentPage = 1;
    _searchQuery = search ?? '';
    _status = status;
    _activeOnly = activeOnly;
    _endsBefore = endsBefore;
    if (filters != null) _filters = filters;

    final gen = ++_generation;
    notifyListeners();

    try {
      final result = await _auctionService.fetchAuctions(
        accessToken: accessToken,
        page: 1,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        status: _status,
        activeOnly: _activeOnly,
        endsBefore: _endsBefore,
        filters: _filters,
      );
      if (gen != _generation) return; // superseded by a newer loadAuctions()
      _auctions = result.auctions;
      _hasMore = result.hasMore;
    } catch (e) {
      if (gen != _generation) return;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (gen == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore({required String accessToken}) async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    _isLoadingMore = true;
    notifyListeners();

    final gen = _generation; // this page belongs to the current filter/search
    try {
      final result = await _auctionService.fetchAuctions(
        accessToken: accessToken,
        page: _currentPage + 1,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        status: _status,
        activeOnly: _activeOnly,
        endsBefore: _endsBefore,
        filters: _filters,
      );
      if (gen != _generation) return; // filters/search changed while this page was in flight
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
