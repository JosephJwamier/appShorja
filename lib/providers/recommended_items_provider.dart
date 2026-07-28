import 'package:flutter/material.dart';
import '../models/listing.dart';
import '../services/item_service.dart';

/// Loads a personalized "recommended for you" feed, ranked by the current
/// user's category interests (home feed section).
class RecommendedItemsProvider extends ChangeNotifier {
  final ItemService _service = ItemService();

  List<FixedListing> _items = [];
  bool _loading = false;
  bool _loaded = false;

  List<FixedListing> get items => _items;
  bool get isLoading => _loading;
  bool get loaded => _loaded;

  Future<void> load({required String? accessToken}) async {
    if (accessToken == null || accessToken.isEmpty) return;
    _loading = true;
    notifyListeners();
    try {
      final result = await _service.fetchRecommendedListingsPaginated(
        accessToken: accessToken,
        pageSize: 10,
      );
      _items = result.listings;
    } catch (_) {
      _items = [];
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }
}
