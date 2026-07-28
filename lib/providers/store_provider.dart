import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/store.dart';
import '../services/store_service.dart';

class StoreProvider extends ChangeNotifier {
  final StoreService _service = StoreService();

  Store? _myStore;
  bool _isCreating = false;
  bool _isUpdating = false;
  String? _errorMessage;

  Store? get myStore => _myStore;
  bool get isCreating => _isCreating;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  Future<({bool success, String message})> createStore({
    required String accessToken,
    required String name,
    required String description,
    XFile? logo,
    XFile? cover,
    int? locationId,
    String? phoneNumber,
    String? whatsappNumber,
  }) async {
    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _service.createStore(
      accessToken: accessToken,
      name: name,
      description: description,
      logo: logo,
      cover: cover,
      locationId: locationId,
      phoneNumber: phoneNumber,
      whatsappNumber: whatsappNumber,
    );

    _isCreating = false;
    if (result.success && result.store != null) {
      _myStore = result.store;
    } else {
      _errorMessage = result.message;
    }
    notifyListeners();

    return (success: result.success, message: result.message);
  }

  Future<({bool success, String message})> updateStore({
    required String accessToken,
    required int storeId,
    required String name,
    required String description,
    required bool isActive,
    XFile? logo,
    XFile? cover,
    int? locationId,
    String? phoneNumber,
    String? whatsappNumber,
  }) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _service.updateStore(
      accessToken: accessToken,
      storeId: storeId,
      name: name,
      description: description,
      isActive: isActive,
      logo: logo,
      cover: cover,
      locationId: locationId,
      phoneNumber: phoneNumber,
      whatsappNumber: whatsappNumber,
    );

    _isUpdating = false;
    if (result.success && result.store != null) {
      _myStore = result.store;
    } else {
      _errorMessage = result.message;
    }
    notifyListeners();

    return (success: result.success, message: result.message);
  }

  Future<({bool success, String message})> toggleActive({
    required String accessToken,
    required int storeId,
    required bool isActive,
  }) async {
    final result = await _service.toggleActive(
      accessToken: accessToken,
      storeId: storeId,
      isActive: isActive,
    );

    if (result.success && _myStore != null) {
      _myStore = _myStore!.copyWith(isActive: isActive);
      notifyListeners();
    }

    return result;
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadMyStore({required String accessToken}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _myStore = await _service.fetchMyStore(accessToken: accessToken);
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
