import 'package:flutter/material.dart';
import '../models/followed_store_group.dart';
import '../models/product.dart';
import '../services/store_service.dart';

/// Loads the stores the current user follows, with a preview of each
/// store's products (home feed).
class FollowingProvider extends ChangeNotifier {
  final StoreService _service = StoreService();

  List<FollowedStoreGroup> _groups = [];
  bool _loading = false;
  bool _loaded = false;

  List<FollowedStoreGroup> get groups => _groups;
  List<Product> get items => _groups.expand((g) => g.items).toList();
  bool get isLoading => _loading;
  bool get loaded => _loaded;

  Future<void> load({required String? accessToken}) async {
    if (accessToken == null || accessToken.isEmpty) return;
    _loading = true;
    notifyListeners();
    try {
      _groups = await _service.fetchFollowingStores(accessToken: accessToken);
    } catch (_) {
      _groups = [];
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }
}
