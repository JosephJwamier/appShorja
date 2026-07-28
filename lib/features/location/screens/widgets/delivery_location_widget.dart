import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/location_model.dart';
import '../../../../theme/app_colors.dart';

/// Read-only compact map widget used in an order detail screen to show the
/// buyer's delivery location.
class DeliveryLocationWidget extends StatelessWidget {
  final LocationModel location;
  final double mapHeight;

  const DeliveryLocationWidget({
    super.key,
    required this.location,
    this.mapHeight = 200,
  });

  Future<void> _openInMaps() async {
    final lat = location.latitude;
    final lng = location.longitude;
    if (lat == null || lng == null) return;

    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    final webUri =
        Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final lat = location.latitude;
    final lng = location.longitude;
    final hasCoords = lat != null && lng != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Map
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: mapHeight,
            child: hasCoords
                ? FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none, // read-only, no gestures
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.balla.app',
                        tileProvider: CancellableNetworkTileProvider(),
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(lat, lng),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppColors.primary,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Container(
                    color: AppColors.surfaceContainerLow,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined,
                            size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'لا تتوفر إحداثيات للخريطة',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        // Address text
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_rounded,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                location.fullAddress.isNotEmpty
                    ? location.fullAddress
                    : location.addressLine1,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        if (location.notes != null && location.notes!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Text(
              location.notes!,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Open in maps button
        if (hasCoords)
          OutlinedButton.icon(
            onPressed: _openInMaps,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('فتح في الخرائط'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
      ],
    );
  }
}
