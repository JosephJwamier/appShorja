import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/item_service.dart';

class MyItemsProvider extends ChangeNotifier {
  final ItemService _itemService = ItemService();

  List<Product> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Product> get items => _items;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyItems({
    required String accessToken,
    required int ownerId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _items = await _itemService.fetchMyItems(
        accessToken: accessToken,
        ownerId: ownerId,
      );
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}