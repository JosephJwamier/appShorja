import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/iraq_governorate.dart';
import '../models/nearby_item_model.dart';
import '../models/nearby_store_model.dart';
import '../providers/location_provider.dart';
import '../utils/map_categories.dart';
import '../../../models/category.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/category_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/category_icons.dart';
import '../../../widgets/app_network_image.dart';
import '../../../screens/item_from_map_screen.dart';
import 'widgets/store_marker_widget.dart';
import 'widgets/item_marker_widget.dart';
import '../services/gps_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  /// المحافظة المختارة من البحث؛ null تعني «حول موقعي».
  IraqGovernorate? _governorate;
  bool get _searchMode => _governorate != null;

  /// التصنيف المختار. يُحفظ كاملاً لا رقمه فقط، كي يبقى زرّه ظاهراً باسمه
  /// ولونه حتى لو لم يبقَ له منتج بعد تضييق النطاق.
  MapCategory? _category;

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
      // أسماء التصنيفات الرئيسية وأيقوناتها للشريط. بدونها نكتفي بما يحمله
      // كل منتج، فلا ننتظرها قبل تحميل الخريطة.
      if (token != null) {
        context.read<CategoryProvider>().loadCategories(accessToken: token);
      }
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

  /// يعالج سبب التعذّر ثم يُعيد المحاولة.
  ///
  /// فتح الإعدادات يُخرج المستخدم من التطبيق، فنُعيد المحاولة عند عودته
  /// بدل أن نطلب منه فتح الخريطة من جديد.
  Future<void> _fixGps(LocationProvider provider) async {
    switch (provider.gpsDenial) {
      case GpsDenial.serviceOff:
        await provider.openLocationSettings();
      case GpsDenial.deniedForever:
        // أندرويد لا يعرض حوار الإذن بعد الرفض النهائي مهما طُلب —
        // إعدادات التطبيق هي الطريق الوحيد.
        await provider.openAppSettings();
      case GpsDenial.denied:
        break; // retryGps يطلب الإذن ثانية بنفسه
      case GpsDenial.none:
        return;
    }

    await provider.retryGps();
    if (!mounted) return;
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
        token: context.read<AuthProvider>().accessToken,
      );
    }
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
    final p = context.read<LocationProvider>();
    final token = context.read<AuthProvider>().accessToken;
    if (_searchMode) {
      await p.searchByGovernorate(_governorate!.name, token: token);
      return;
    }
    if (p.currentLat == null) return;
    await p.loadNearby(lat: p.currentLat!, lng: p.currentLng!, token: token);
  }

  // ── Governorate search ───────────────────────────────────────────────────
  // Recentering the map no longer depends on the search results having
  // coordinates (the old free-text city search did, and silently did
  // nothing when it couldn't find a match) — picking a governorate always
  // moves the map to its known center immediately, then loads matching
  // items/stores separately.
  Future<void> _selectGovernorate(IraqGovernorate governorate) async {
    FocusScope.of(context).unfocus();
    setState(() => _governorate = governorate);
    _mapController.move(governorate.center, 11);
    final token = context.read<AuthProvider>().accessToken;
    await context.read<LocationProvider>().searchByGovernorate(
      governorate.name,
      token: token,
    );
  }

  void _clearGovernorateSearch() {
    setState(() => _governorate = null);
    _reloadNearby();
  }

  // ── Category filter ──────────────────────────────────────────────────────
  void _selectCategory(MapCategory? category, Map<int, Category> byId) {
    // الضغط على التصنيف المختار نفسه يلغيه — أسرع من البحث عن زرّ «الكل».
    final next = category?.id == _category?.id ? null : category;
    setState(() => _category = next);
    if (next == null) return;

    final matching = context
        .read<LocationProvider>()
        .nearbyItems
        .where((i) => itemMatchesCategory(i, next.id, byId))
        .toList();
    _focusOn(matching);
  }

  /// يقرّب الخريطة لتُظهر منتجات التصنيف المختار كلها دفعةً واحدة، مع ترك
  /// هامش تحت الشريط العلوي وفوق اللوحة السفلية كي لا تختفي علامة خلفهما.
  void _focusOn(List<NearbyItem> items) {
    final points = [
      for (final i in items)
        if (i.currentLocation?.latitude != null &&
            i.currentLocation?.longitude != null)
          LatLng(i.currentLocation!.latitude!, i.currentLocation!.longitude!),
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    final top = MediaQuery.paddingOf(context).top;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: EdgeInsets.fromLTRB(56, top + 140, 56, 300),
        maxZoom: 16,
      ),
    );
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

  List<Marker> _itemMarkers(List<NearbyItem> items, Map<int, Category> byId) {
    final clusters = _clusterItems(items);
    final markers = <Marker>[];

    for (final entry in clusters.entries) {
      final group = entry.value;
      final loc = group.first.currentLocation!;
      final point = LatLng(loc.latitude!, loc.longitude!);
      final roots = group.map((i) => rootCategoryIdOf(i, byId)).toSet();

      if (group.length == 1) {
        markers.add(
          Marker(
            point: point,
            width: 50,
            height: 58,
            child: ItemMarkerWidget(
              item: group.first,
              accent: colorForCategory(roots.first),
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
              // تجمّع مختلط التصنيفات بلون محايد: تلوينه بلون أحدها يكذب.
              accent: roots.length == 1
                  ? colorForCategory(roots.first)
                  : AppColors.inverseSurface,
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
    final byId = {
      for (final c in context.watch<CategoryProvider>().categories) c.id: c,
    };

    return Scaffold(
      body: Consumer<LocationProvider>(
        builder: (context, provider, _) {
          final lat = provider.currentLat;
          final lng = provider.currentLng;
          final showItems = provider.filter != MapFilter.stores;
          final showStores = provider.filter != MapFilter.items;

          final categories = mapCategoriesFor(provider.nearbyItems, byId);
          final visibleItems = provider.nearbyItems
              .where((i) => itemMatchesCategory(i, _category?.id, byId))
              .toList();
          final storeMarkers = _storeMarkers(provider.nearbyStores);
          final itemMarkers = _itemMarkers(visibleItems, byId);
          final itemsOnMap = visibleItems
              .where((i) =>
                  i.currentLocation?.latitude != null &&
                  i.currentLocation?.longitude != null)
              .length;

          final noGps = !provider.gpsReady &&
              lat == null &&
              !provider.isLoadingNearby &&
              !_searchMode;

          return Stack(
            children: [
              // ── Flutter Map ─────────────────────────────────────────────
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _baghdad,
                  initialZoom: 12,
                  minZoom: 4,
                  maxZoom: 18,
                  onTap: (_, _) => FocusScope.of(context).unfocus(),
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
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderColor: AppColors.primary.withValues(
                            alpha: 0.35,
                          ),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),

                  if (showStores) MarkerLayer(markers: storeMarkers),
                  if (showItems) MarkerLayer(markers: itemMarkers),

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

              // ── Top: search + categories ───────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // شريط السبب: يظهر فقط حين يتعذّر الموقع. بدونه
                        // تستقرّ الخريطة على بغداد صامتةً، فيظنّ المستخدم
                        // أن لا بضاعة قربه بينما التطبيق لا يعرف أين هو.
                        if (provider.gpsDenial != GpsDenial.none)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: _GpsDenialBanner(
                              denial: provider.gpsDenial,
                              onFix: () => _fixGps(provider),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              if (Navigator.canPop(context)) ...[
                                _RoundIconButton(
                                  icon: Icons.arrow_back_rounded,
                                  tooltip: 'رجوع',
                                  onTap: () => Navigator.maybePop(context),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: _GovernorateSearchBar(
                                  loading: provider.isLoadingNearby,
                                  onSelected: _selectGovernorate,
                                  onClear: _clearGovernorateSearch,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showItems &&
                            (categories.isNotEmpty || _category != null)) ...[
                          const SizedBox(height: 10),
                          _CategoryStrip(
                            categories: categories,
                            selected: _category,
                            totalCount: provider.nearbyItems.length,
                            onSelected: (c) => _selectCategory(c, byId),
                          ),
                        ],
                        if (provider.nearbyError != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                            child: _ErrorBanner(
                              message: provider.nearbyError!,
                              onClose: provider.clearNearbyError,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Bottom: recenter + control panel ───────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _RoundIconButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'موقعي الحالي',
                        iconColor: AppColors.primary,
                        size: 48,
                        onTap: _reCenter,
                      ),
                    ),
                    // إذن الموقع ممنوح لكن القراءة فشلت: البحث بالمحافظة
                    // لا يحتاج GPS، فهو الطريق للتصفّح في هذه الحالة.
                    if (noGps && provider.gpsDenial == GpsDenial.none)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _NoGpsNotice(),
                      ),
                    _ControlPanel(
                      summary: _summary(
                        provider: provider,
                        storeCount: showStores ? storeMarkers.length : 0,
                        itemCount: showItems ? itemsOnMap : 0,
                      ),
                      filter: provider.filter,
                      onFilterChanged: (f) async {
                        provider.setFilter(f);
                        await _reloadNearby();
                      },
                      showRadius: !_searchMode,
                      radiusKm: provider.radiusKm,
                      onRadiusChanged: provider.setRadius,
                      onRadiusChangeEnd: _reloadNearby,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// سطرا اللوحة السفلية: ماذا يظهر الآن، وأين، وماذا يفعل المستخدم إن
  /// كانت الخريطة فارغة — لا «لا توجد نتائج» وحدها.
  (String, String) _summary({
    required LocationProvider provider,
    required int storeCount,
    required int itemCount,
  }) {
    if (provider.isLoadingNearby) return ('جارٍ البحث…', 'نحمّل ما حولك');

    final where = _searchMode
        ? 'في ${_governorate!.name}'
        : 'ضمن ${provider.radiusKm.toInt()} كم منك';
    final parts = [
      if (itemCount > 0) '$itemCount منتج',
      if (storeCount > 0) '$storeCount متجر',
    ];
    final cat = provider.filter != MapFilter.stores ? _category : null;

    if (parts.isNotEmpty) {
      return (
        parts.join(' · '),
        cat != null ? 'من «${cat.name}» $where' : where,
      );
    }
    if (cat != null) {
      return (
        'لا منتجات من «${cat.name}» $where',
        _searchMode
            ? 'اختر تصنيفاً آخر أو محافظة أخرى'
            : 'وسّع النطاق أو اختر تصنيفاً آخر',
      );
    }
    final loadedSomething =
        provider.nearbyItems.isNotEmpty || provider.nearbyStores.isNotEmpty;
    if (loadedSomething) {
      return ('النتائج بلا موقع على الخريطة', 'لم يحدّد أصحابها مكانها بعد');
    }
    if (!_searchMode && provider.currentLat == null) {
      return ('لا نعرف موقعك بعد', 'اختر محافظة من البحث للتصفّح');
    }
    return (
      'لا شيء $where',
      _searchMode ? 'جرّب محافظة أخرى' : 'وسّع النطاق أو اختر محافظة',
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

// ── Shared floating surface ──────────────────────────────────────────────────
// ظلّ واحد لكل ما يطفو فوق الخريطة، كي تبدو الطبقات من عائلة واحدة.
List<BoxShadow> get _floatShadow => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.10),
    blurRadius: 12,
    offset: const Offset(0, 3),
  ),
];

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color iconColor;
  final double size;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconColor = AppColors.onSurface,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: _floatShadow,
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Search bar ───────────────────────────────────────────────────────────────
// Restricted to the fixed governorate list (see [iraqGovernorates]) instead
// of free text, so a selection is guaranteed to recenter the map and match
// real search results — typing an arbitrary city name used to silently do
// nothing when it didn't happen to match any stored location text exactly.
class _GovernorateSearchBar extends StatelessWidget {
  final bool loading;
  final ValueChanged<IraqGovernorate> onSelected;
  final VoidCallback onClear;

  const _GovernorateSearchBar({
    required this.loading,
    required this.onSelected,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<IraqGovernorate>(
      displayStringForOption: (g) => g.name,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim();
        // حقل فارغ مركَّز يعرض المحافظات كلها: كثيرون لا يعرفون أن عليهم
        // الكتابة أولاً، والقائمة 18 اسماً فقط.
        if (q.isEmpty) return iraqGovernorates;
        return iraqGovernorates.where((g) => g.name.contains(q));
      },
      onSelected: onSelected,
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 6,
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                      title: Text(
                        g.name,
                        style: const TextStyle(fontSize: 14),
                      ),
                      onTap: () => onSelectedOption(g),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: _floatShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'ابحث في محافظة أخرى',
                    hintStyle: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.primary,
                    ),
                    suffixIcon: value.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'العودة إلى ما حولي',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              controller.clear();
                              focusNode.unfocus();
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
              ),
              // شريط التحميل داخل حافة البحث السفلية بدل خطّ عائم أعلى
              // الشاشة يختفي تحت شريط الحالة.
              if (loading)
                const Positioned(
                  left: 24,
                  right: 24,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2.5,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primaryFixed,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Category strip ───────────────────────────────────────────────────────────
class _CategoryStrip extends StatelessWidget {
  final List<MapCategory> categories;
  final MapCategory? selected;
  final int totalCount;
  final ValueChanged<MapCategory?> onSelected;

  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.totalCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // التصنيف المختار يبقى في الشريط وإن لم يعد له منتج في النطاق الجديد،
    // وإلا اختفى الزرّ الذي يُلغيه.
    final list = [
      if (selected != null && categories.every((c) => c.id != selected!.id))
        MapCategory(
          id: selected!.id,
          name: selected!.name,
          iconCode: selected!.iconCode,
          iconUrl: selected!.iconUrl,
          color: selected!.color,
          count: 0,
        ),
      ...categories,
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: list.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _CategoryChip(
              label: 'الكل',
              count: totalCount,
              color: AppColors.inverseSurface,
              leading: const Icon(Icons.apps_rounded, size: 17),
              selected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final c = list[i - 1];
          return _CategoryChip(
            label: c.name,
            count: c.count,
            color: c.color,
            leading: _categoryLeading(c),
            selected: selected?.id == c.id,
            onTap: () => onSelected(c),
          );
        },
      ),
    );
  }

  Widget? _categoryLeading(MapCategory c) {
    if (c.iconUrl != null) {
      return ClipOval(
        child: SizedBox(
          width: 20,
          height: 20,
          child: AppNetworkImage(
            c.iconUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    final icon = categoryIconFor(c.iconCode);
    return icon != null ? Icon(icon, size: 17) : null;
  }
}

/// زرّ تصنيف. لونه هو لون علامات منتجاته على الخريطة نفسه، فيعرف المستخدم
/// بنظرة أيّ علامة تنتمي لأيّ تصنيف حتى قبل أن يختار.
class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.leading,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label، $count منتج',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: _floatShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(color: selected ? Colors.white : color),
                child:
                    leading ??
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : color,
                        shape: BoxShape.circle,
                      ),
                    ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom control panel ─────────────────────────────────────────────────────
class _ControlPanel extends StatelessWidget {
  final (String, String) summary;
  final MapFilter filter;
  final ValueChanged<MapFilter> onFilterChanged;
  final bool showRadius;
  final double radiusKm;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onRadiusChangeEnd;

  const _ControlPanel({
    required this.summary,
    required this.filter,
    required this.onFilterChanged,
    required this.showRadius,
    required this.radiusKm,
    required this.onRadiusChanged,
    required this.onRadiusChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = summary;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Column(
              key: ValueKey(title + subtitle),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _LayerToggle(current: filter, onChanged: onFilterChanged),
          if (showRadius) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.radar_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.primaryFixed,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.12),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      min: 1,
                      max: 50,
                      divisions: 49,
                      value: radiusKm,
                      label: '${radiusKm.toInt()} كم',
                      onChanged: onRadiusChanged,
                      onChangeEnd: (_) => onRadiusChangeEnd(),
                    ),
                  ),
                ),
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${radiusKm.toInt()} كم',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// ماذا تعرض الخريطة: متاجر، منتجات، أو كلاهما.
class _LayerToggle extends StatelessWidget {
  final MapFilter current;
  final ValueChanged<MapFilter> onChanged;

  const _LayerToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _segment(MapFilter.items, 'المنتجات', Icons.sell_rounded),
          _segment(MapFilter.both, 'الكل', Icons.layers_rounded),
          _segment(MapFilter.stores, 'المتاجر', Icons.storefront_rounded),
        ],
      ),
    );
  }

  Widget _segment(MapFilter f, String label, IconData icon) {
    final selected = current == f;
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: () => onChanged(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notices ──────────────────────────────────────────────────────────────────
class _NoGpsNotice extends StatelessWidget {
  const _NoGpsNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: _floatShadow,
      ),
      child: const Row(
        children: [
          Icon(Icons.location_off_rounded, color: AppColors.error, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'تعذّر تحديد موقعك — اختر محافظتك من شريط البحث',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _ErrorBanner({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.onErrorContainer,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              tooltip: 'إغلاق',
              icon: const Icon(
                Icons.close_rounded,
                color: AppColors.onErrorContainer,
                size: 18,
              ),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط يشرح لماذا لا يُعرف الموقع، ويحمل زرّ العلاج المناسب لكل سبب.
class _GpsDenialBanner extends StatelessWidget {
  final GpsDenial denial;
  final VoidCallback onFix;

  const _GpsDenialBanner({required this.denial, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final (text, action) = switch (denial) {
      GpsDenial.serviceOff => (
          'خدمة الموقع مطفأة — شغّلها لعرض ما حولك',
          'تشغيل',
        ),
      GpsDenial.deniedForever => (
          'إذن الموقع مرفوض — فعّله من إعدادات التطبيق',
          'الإعدادات',
        ),
      GpsDenial.denied => (
          'نحتاج إذن الموقع لعرض البضاعة القريبة منك',
          'السماح',
        ),
      GpsDenial.none => ('', ''),
    };

    return Material(
      color: AppColors.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
            start: 14, end: 6, top: 6, bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined,
                size: 20, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.onSurface),
              ),
            ),
            TextButton(
              onPressed: onFix,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(action,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
