import 'package:flutter/material.dart';
import '../models/listing.dart';
import '../services/item_service.dart';

class ItemsProvider extends ChangeNotifier {
  final ItemService _itemService = ItemService();

  List<FixedListing> _listings = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<FixedListing> get listings => _listings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadListings({required String accessToken}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _listings = await _itemService.fetchFixedListings(accessToken: accessToken);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}