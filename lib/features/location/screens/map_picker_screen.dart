import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../theme/app_colors.dart';

class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;

  const MapPickerScreen({super.key, this.initial});

  static Future<LatLng?> pick(BuildContext context, {LatLng? initial}) =>
      Navigator.push<LatLng>(
        context,
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(initial: initial),
        ),
      );

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  static const LatLng _baghdad = LatLng(33.3128, 44.3614);

  late LatLng _center;
  bool _loadingGps = false;
  bool _isMoving = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initial ?? _baghdad;
  }

  Future<void> _goToMyLocation() async {
    setState(() => _loadingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('الرجاء السماح بالوصول للموقع من الإعدادات')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      final latLng = LatLng(pos.latitude, pos.longitude);
      _mapController.move(latLng, 17);
      setState(() => _center = latLng);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديد موقعك الحالي')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // ── الخارطة ──────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onMapEvent: (event) {
                if (event is MapEventMoveStart ||
                    event is MapEventScrollWheelZoom) {
                  if (!_isMoving) setState(() => _isMoving = true);
                } else if (event is MapEventMoveEnd ||
                    event is MapEventFlingAnimationEnd ||
                    event is MapEventDoubleTapZoomEnd) {
                  setState(() {
                    _isMoving = false;
                    _center = event.camera.center;
                  });
                } else if (event is MapEventMove) {
                  setState(() => _center = event.camera.center);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.balla.app',
                tileProvider: CancellableNetworkTileProvider(),
              ),
            ],
          ),

          // ── دبوس المركز ──────────────────────────────────────────────────
          IgnorePointer(
            child: Center(
              child: AnimatedSlide(
                offset: Offset(0, _isMoving ? -0.08 : 0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: AnimatedScale(
                  scale: _isMoving ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.primary,
                          size: 30,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _isMoving ? 6 : 10,
                        height: _isMoving ? 3 : 5,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── شريط علوي شفاف ───────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(12, top + 10, 12, 20),
              child: Row(
                children: [
                  _CircleBtn(
                    icon: Icons.arrow_back_ios,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          'حرّك الخارطة لتحديد موقعك',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),

          // ── زر الموقع الحالي ─────────────────────────────────────────────
          Positioned(
            left: 16,
            bottom: 140 + bottom,
            child: FloatingActionButton.extended(
              heroTag: 'gps_fab',
              onPressed: _loadingGps ? null : _goToMyLocation,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              elevation: 4,
              icon: _loadingGps
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.primary),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: Text(
                _loadingGps ? 'جارٍ التحديد...' : 'موقعي الحالي',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // ── بطاقة التأكيد السفلية ─────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 16,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── مقبض سحب ──────────────────────────────────────────
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── الإحداثيات ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.gps_fixed_rounded,
                            color: AppColors.primary, size: 17),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_center.latitude.toStringAsFixed(6)},  '
                            '${_center.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.onSurface,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (_isMoving)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── زر التأكيد ────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isMoving
                          ? null
                          : () => Navigator.pop(context, _center),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 22),
                      label: const Text(
                        'تأكيد الموقع',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── زر دائري ─────────────────────────────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppColors.onSurface),
      ),
    );
  }
}
