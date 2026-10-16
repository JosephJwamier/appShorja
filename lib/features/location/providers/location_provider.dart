import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import '../models/nearby_item_model.dart';
import '../models/nearby_store_model.dart';
import '../services/location_api_service.dart';
import '../services/gps_service.dart';

enum MapFilter { stores, items, both }

class LocationProvider extends ChangeNotifier {
  final LocationApiService _api = LocationApiService();
  final GpsService _gps = GpsService();

  // ── My saved locations ──────────────────────────────────────────────────
  List<LocationModel> _myLocations = [];
  bool _isLoadingLocations = false;
  String? _locationsError;

  List<LocationModel> get myLocations => _myLocations;
  bool get isLoadingLocations => _isLoadingLocations;
  String? get locationsError => _locationsError;

  LocationModel? get primaryLocation =>
      _myLocations.where((l) => l.isPrimary).firstOrNull;

  // ── Nearby data ─────────────────────────────────────────────────────────
  List<NearbyItem> _nearbyItems = [];
  List<NearbyStore> _nearbyStores = [];
  bool _isLoadingNearby = false;
  String? _nearbyError;

  List<NearbyItem> get nearbyItems => _nearbyItems;
  List<NearbyStore> get nearbyStores => _nearbyStores;
  bool get isLoadingNearby => _isLoadingNearby;
  String? get nearbyError => _nearbyError;

  // ── GPS ─────────────────────────────────────────────────────────────────
  double? _currentLat;
  double? _currentLng;
  bool _gpsReady = false;
  GpsDenial _gpsDenial = GpsDenial.none;

  double? get currentLat => _currentLat;
  double? get currentLng => _currentLng;
  bool get gpsReady => _gpsReady;

  /// سبب تعذّر الموقع — تعرضه الخريطة مع علاجه بدل أن تصمت على بغداد.
  GpsDenial get gpsDenial => _gpsDenial;

  // ── Map settings ────────────────────────────────────────────────────────
  double _radiusKm = 10.0;
  MapFilter _filter = MapFilter.both;

  double get radiusKm => _radiusKm;
  MapFilter get filter => _filter;

  // ── GPS init ─────────────────────────────────────────────────────────────
  Future<void> initGps() async {
    // يُطلب الإذن أولاً ويُحتفظ بسبب الرفض: getCurrentPosition وحدها
    // تُرجع null لثلاثة أسباب مختلفة، ولا شيء يميّزها بعدها.
    _gpsDenial = await _gps.ensurePermission();
    if (_gpsDenial != GpsDenial.none) {
      _gpsReady = false;
      notifyListeners();
      return;
    }

    final position = await _gps.getCurrentPosition();
    if (position != null) {
      _currentLat = position.latitude;
      _currentLng = position.longitude;
      _gpsReady = true;
    } else {
      // الإذن مُنح لكن القراءة فشلت (مهلة، أو جهاز بلا إشارة بعد).
      _gpsReady = false;
    }
    notifyListeners();
  }

  /// يُعيد المحاولة بعد أن يعالج المستخدم السبب (شغّل الخدمة أو منح الإذن).
  Future<void> retryGps() => initGps();

  Future<void> openLocationSettings() => _gps.openLocationSettings();
  Future<void> openAppSettings() => _gps.openAppSettings();

  // ── My locations CRUD ────────────────────────────────────────────────────
  Future<void> loadMyLocations(String token) async {
    _isLoadingLocations = true;
    _locationsError = null;
    notifyListeners();

    try {
      _myLocations = await _api.listLocations(token: token);
    } catch (e) {
      _locationsError = _msg(e);
    } finally {
      _isLoadingLocations = false;
      notifyListeners();
    }
  }

  Future<bool> createLocation(String token, Map<String, dynamic> data) async {
    try {
      await _api.createLocation(token: token, data: data);
      await loadMyLocations(token);
      return true;
    } catch (e) {
      _locationsError = _msg(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateLocation(
    String token,
    int id,
    Map<String, dynamic> data,
  ) async {
    try {
      await _api.updateLocation(token: token, id: id, data: data);
      await loadMyLocations(token);
      return true;
    } catch (e) {
      _locationsError = _msg(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteLocation(String token, int id) async {
    try {
      await _api.deleteLocation(token: token, id: id);
      _myLocations.removeWhere((l) => l.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _locationsError = _msg(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> setPrimaryLocation(String token, int id) async {
    try {
      await _api.setPrimaryLocation(token: token, id: id);
      // Reload to get correct isPrimary flags across all locations
      await loadMyLocations(token);
      return true;
    } catch (e) {
      _locationsError = _msg(e);
      notifyListeners();
      return false;
    }
  }

  // ── Nearby search ────────────────────────────────────────────────────────
  Future<void> loadNearby({
    required double lat,
    required double lng,
    double? radius,
    String? token,
  }) async {
    final r = radius ?? _radiusKm;
    _isLoadingNearby = true;
    _nearbyError = null;
    notifyListeners();

    try {
      await Future.wait([
        if (_filter == MapFilter.items || _filter == MapFilter.both)
          _api
              .getNearbyItems(lat: lat, lng: lng, radius: r, token: token)
              .then((v) => _nearbyItems = v),
        if (_filter == MapFilter.stores || _filter == MapFilter.both)
          _api
              .getNearbyStores(lat: lat, lng: lng, radius: r, token: token)
              .then((v) => _nearbyStores = v),
      ]);
    } catch (e) {
      _nearbyError = _msg(e);
    } finally {
      _isLoadingNearby = false;
      notifyListeners();
    }
  }

  /// Search by a fixed governorate name (see [iraqGovernorates]) — an exact
  /// match against `Location.state`, unlike free-text city search.
  Future<void> searchByGovernorate(String governorate, {String? token}) async {
    _isLoadingNearby = true;
    _nearbyError = null;
    notifyListeners();

    try {
      await Future.wait([
        if (_filter == MapFilter.items || _filter == MapFilter.both)
          _api
              .getItemsByGovernorate(
                governorate: governorate,
                status: 'active',
                token: token,
              )
              .then((v) => _nearbyItems = v),
        if (_filter == MapFilter.stores || _filter == MapFilter.both)
          _api
              .getStoresByGovernorate(governorate: governorate, token: token)
              .then((v) => _nearbyStores = v),
      ]);
    } catch (e) {
      _nearbyError = _msg(e);
    } finally {
      _isLoadingNearby = false;
      notifyListeners();
    }
  }

  void setRadius(double km) {
    _radiusKm = km;
    notifyListeners();
  }

  void setFilter(MapFilter f) {
    _filter = f;
    if (f == MapFilter.stores) _nearbyItems = [];
    if (f == MapFilter.items) _nearbyStores = [];
    notifyListeners();
  }

  void clearNearbyError() {
    _nearbyError = null;
    notifyListeners();
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');
}
