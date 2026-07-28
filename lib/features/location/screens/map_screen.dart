import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/iraq_governorate.dart';
import '../models/nearby_item_model.dart';
import '../models/nearby_store_model.dart';
import '../providers/location_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../screens/item_from_map_screen.dart';
import 'widgets/store_marker_widget.dart';
import 'widgets/item_marker_widget.dart';
import 'widgets/radius_slider_widget.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  bool _searchMode = false; // true when showing governorate-search results

  // Default center: Baghdad
  static const LatLng _baghdad = LatLng(33.3128, 44.3614);

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<LocationProvider>();
      final token = context.read<AuthProvider>().accessToken;
      await provider.initGps();
      if (provider.gpsReady &&
          provider.currentLat != null &&
          provider.currentLng != null) {
        _mapController.move(
          LatLng(provider.currentLat!, provider.currentLng!),
          13,
        );
        await provider.loadNearby(
          lat: provider.currentLat!,
          lng: provider.currentLng!,
          token: token,
        );
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Re-center on user location ────────────────────────────────────────────
  void _reCenter() {
    final p = context.read<LocationProvider>();
    if (p.currentLat != null && p.currentLng != null) {
      _mapController.move(LatLng(p.currentLat!, p.currentLng!), 14);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذّر تحديد موقعك الحالي')));
    }
  }

  // ── Reload nearby with updated radius ────────────────────────────────────
  Future<void> _reloadNearby() async {
    if (_searchMode) return;
    final p = context.read<LocationProvider>();
    if (p.currentLat == null) return;
    final token = context.read<AuthProvider>().accessToken;
    await p.loadNearby(lat: p.currentLat!, lng: p.currentLng!, token: token);
  }

  // ── Governorate search ───────────────────────────────────────────────────
  // Recentering the map no longer depends on the search results having
  // coordinates (the old free-text city search did, and silently did
  // nothing when it couldn't find a match) — picking a governorate always
  // moves the map to its known center immediately, then loads matching
  // items/stores separately.
  Future<void> _selectGovernorate(IraqGovernorate governorate) async {
    setState(() => _searchMode = true);
    _mapController.move(governorate.center, 11);
    final token = context.read<AuthProvider>().accessToken;
    await context.read<LocationProvider>().searchByGovernorate(
      governorate.name,
      token: token,
    );
  }

  void _clearGovernorateSearch() {
    setState(() => _searchMode = false);
    _reloadNearby();
  }

  // ── Cluster items by rounded coordinates (~50m grid) ────────────────────
  Map<String, List<NearbyItem>> _clusterItems(List<NearbyItem> items) {
    final clusters = <String, List<NearbyItem>>{};
    for (final item in items) {
      final loc = item.currentLocation;
      if (loc?.latitude == null || loc?.longitude == null) continue;
      final key =
          '${loc!.latitude!.toStringAsFixed(4)},${loc.longitude!.toStringAsFixed(4)}';
      clusters.putIfAbsent(key, () => []).add(item);
    }
    return clusters;
  }

  // ── Marker tap sheets ────────────────────────────────────────────────────
  void _showStoreSheet(NearbyStore store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize: 0.2,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) =>
            StoreMarkerSheet(store: store, scrollController: scrollCtrl),
      ),
    );
  }

  void _showItemSheet(NearbyItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize: 0.2,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => ItemMarkerSheet(
          item: item,
          scrollController: scrollCtrl,
          onViewDetails: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ItemFromMapScreen(item: item)),
            );
          },
        ),
      ),
    );
  }

  void _showClusterSheet(List<NearbyItem> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => ItemClusterSheet(
          items: items,
          scrollController: scrollCtrl,
          onViewDetails: (item) {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ItemFromMapScreen(item: item)),
            );
          },
        ),
      ),
    );
  }

  // ── Build markers ────────────────────────────────────────────────────────
  List<Marker> _storeMarkers(List<NearbyStore> stores) {
    return stores
        .where((s) {
          final loc = s.defaultLocation;
          return loc?.latitude != null && loc?.longitude != null;
        })
        .map(
          (s) => Marker(
            point: LatLng(
              s.defaultLocation!.latitude!,
              s.defaultLocation!.longitude!,
            ),
            width: 44,
            height: 50,
            child: StoreMarkerWidget(store: s, onTap: () => _showStoreSheet(s)),
          ),
        )
        .toList();
  }

  List<Marker> _itemMarkers(List<NearbyItem> items) {
    final clusters = _clusterItems(items);
    final markers = <Marker>[];

    for (final entry in clusters.entries) {
      final group = entry.value;
      final loc = group.first.currentLocation!;
      final point = LatLng(loc.latitude!, loc.longitude!);

      if (group.length == 1) {
        markers.add(
          Marker(
            point: point,
            width: 50,
            height: 58,
            child: ItemMarkerWidget(
              item: group.first,
              onTap: () => _showItemSheet(group.first),
            ),
          ),
        );
      } else {
        markers.add(
          Marker(
            point: point,
            width: 80,
            height: 48,
            child: ItemClusterMarker(
              count: group.length,
              onTap: () => _showClusterSheet(group),
            ),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<LocationProvider>(
        builder: (context, provider, _) {
          final lat = provider.currentLat;
          final lng = provider.currentLng;
          final storeMarkers = _storeMarkers(provider.nearbyStores);
          final itemMarkers = _itemMarkers(provider.nearbyItems);

          return Stack(
            children: [
              // ── Flutter Map ─────────────────────────────────────────────
              FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: _baghdad,
                  initialZoom: 12,
                  minZoom: 4,
                  maxZoom: 18,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.balla.app',
                    tileProvider: CancellableNetworkTileProvider(),
                  ),

                  // Radius circle around user location
                  if (lat != null && lng != null && !_searchMode)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(lat, lng),
                          radius: provider.radiusKm * 1000,
                          useRadiusInMeter: true,
                          color: AppColors.primary.withValues(alpha: 0.07),
                          borderColor: AppColors.primary.withValues(
                            alpha: 0.35,
                          ),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),

                  // Store markers
                  if (provider.filter != MapFilter.items)
                    MarkerLayer(markers: storeMarkers),

                  // Item markers
                  if (provider.filter != MapFilter.stores)
                    MarkerLayer(markers: itemMarkers),

                  // Pulsing user location dot
                  if (lat != null && lng != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 36,
                          height: 36,
                          child: _PulsingDot(animation: _pulseAnim),
                        ),
                      ],
                    ),
                ],
              ),

              // ── Loading bar ─────────────────────────────────────────────
              if (provider.isLoadingNearby)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.primaryFixed,
                  ),
                ),

              // ── Search bar ──────────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 12,
                right: 12,
                child: _GovernorateSearchBar(
                  onSelected: _selectGovernorate,
                  onClear: _clearGovernorateSearch,
                ),
              ),

              // ── Filter toggle ────────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                left: 0,
                right: 0,
                child: Center(
                  child: _FilterChips(
                    current: provider.filter,
                    onChanged: (f) async {
                      provider.setFilter(f);
                      await _reloadNearby();
                    },
                  ),
                ),
              ),

              // ── No-GPS notice ─────────────────────────────────────────────
              // The governorate search bar above doesn't need GPS at all, so
              // it's the way to browse when location permission is denied.
              if (!provider.gpsReady &&
                  lat == null &&
                  !provider.isLoadingNearby &&
                  !_searchMode)
                Positioned(
                  bottom: 180,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.location_off_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'لم يُمنح إذن الموقع — استخدم شريط البحث أعلاه لاختيار محافظتك',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Error snack ──────────────────────────────────────────────
              if (provider.nearbyError != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 130,
                  left: 12,
                  right: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.nearbyError!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: provider.clearNearbyError,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Stats bubble ─────────────────────────────────────────────
              if (!provider.isLoadingNearby)
                Positioned(
                  bottom: 170,
                  left: 12,
                  child: _StatsBubble(
                    storeCount: storeMarkers.length,
                    itemCount: itemMarkers.length,
                    totalStores: provider.nearbyStores.length,
                    totalItems: provider.nearbyItems.length,
                    filter: provider.filter,
                  ),
                ),

              // ── Radius slider ─────────────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: RadiusSliderWidget(
                  radiusKm: provider.radiusKm,
                  onChanged: (v) => provider.setRadius(v),
                  onChangeEnd: _reloadNearby,
                ),
              ),
            ],
          );
        },
      ),

      // ── FAB: re-center ──────────────────────────────────────────────────
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 165),
        child: FloatingActionButton(
          mini: true,
          onPressed: _reCenter,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          elevation: 4,
          tooltip: 'موقعي الحالي',
          child: const Icon(Icons.my_location_rounded),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ── Pulsing blue user-location dot ──────────────────────────────────────────
class _PulsingDot extends AnimatedWidget {
  const _PulsingDot({required Animation<double> animation})
    : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 36 * t,
          height: 36 * t,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withValues(alpha: 0.25 * (1 - t + 0.4)),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.shade700,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.4),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Search bar ───────────────────────────────────────────────────────────────
// Restricted to the fixed governorate list (see [iraqGovernorates]) instead
// of free text, so a selection is guaranteed to recenter the map and match
// real search results — typing an arbitrary city name used to silently do
// nothing when it didn't happen to match any stored location text exactly.
class _GovernorateSearchBar extends StatelessWidget {
  final ValueChanged<IraqGovernorate> onSelected;
  final VoidCallback onClear;

  const _GovernorateSearchBar({
    required this.onSelected,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<IraqGovernorate>(
      displayStringForOption: (g) => g.name,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim();
        if (q.isEmpty) return const Iterable<IraqGovernorate>.empty();
        return iraqGovernorates.where((g) => g.name.contains(q));
      },
      onSelected: onSelected,
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final g = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_city_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    title: Text(g.name, textDirection: TextDirection.rtl),
                    onTap: () => onSelectedOption(g),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textDirection: TextDirection.rtl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'اختر محافظة...',
              hintTextDirection: TextDirection.rtl,
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.primary,
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onClear();
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Filter chips ──────────────────────────────────────────────────────────────
class _FilterChips extends StatelessWidget {
  final MapFilter current;
  final ValueChanged<MapFilter> onChanged;

  const _FilterChips({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(MapFilter.stores, 'متاجر', Icons.store_rounded),
          _chip(MapFilter.both, 'الاثنين', Icons.layers_rounded),
          _chip(MapFilter.items, 'منتجات', Icons.sell_rounded),
        ],
      ),
    );
  }

  Widget _chip(MapFilter f, String label, IconData icon) {
    final selected = current == f;
    return GestureDetector(
      onTap: () => onChanged(f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats bubble ──────────────────────────────────────────────────────────────
class _StatsBubble extends StatelessWidget {
  final int storeCount;
  final int itemCount;
  final int totalStores;
  final int totalItems;
  final MapFilter filter;

  const _StatsBubble({
    required this.storeCount,
    required this.itemCount,
    required this.totalStores,
    required this.totalItems,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (filter != MapFilter.items) {
      parts.add(storeCount > 0 ? '$storeCount متجر' : '');
    }
    if (filter != MapFilter.stores) {
      parts.add(itemCount > 0 ? '$itemCount منتج' : '');
    }
    final visibleParts = parts.where((p) => p.isNotEmpty).toList();

    // Nothing loaded at all
    final nothingLoaded = totalItems == 0 && totalStores == 0;
    // Loaded but nothing has coordinates
    final noCoords = !nothingLoaded && visibleParts.isEmpty;

    String label;
    Color bg;
    if (visibleParts.isNotEmpty) {
      label = visibleParts.join(' · ');
      bg = Colors.white;
    } else if (noCoords) {
      label = 'المنتجات المحملة لا تحتوي موقعاً';
      bg = Colors.orange.shade50;
    } else {
      label = 'لا توجد نتائج قريبة';
      bg = Colors.white;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: noCoords ? Colors.orange.shade800 : AppColors.onSurface,
        ),
      ),
    );
  }
}
