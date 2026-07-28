import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/location_model.dart';
import '../providers/location_provider.dart';
import 'add_edit_location_screen.dart';
import '../../../theme/app_colors.dart';

/// A delivery/pickup location chosen for an order or reservation — always
/// backed by one of the buyer's saved [LocationModel] entries (free-form map
/// coordinates are not supported; the buyer must pick a saved address or
/// add a new one).
class LocationPickerResult {
  final int locationId;
  final double? lat;
  final double? lng;
  final String address;

  const LocationPickerResult({
    required this.locationId,
    this.lat,
    this.lng,
    required this.address,
  });

  factory LocationPickerResult.fromLocation(LocationModel loc) {
    return LocationPickerResult(
      locationId: loc.id,
      lat: loc.latitude,
      lng: loc.longitude,
      address: loc.fullAddress.isNotEmpty ? loc.fullAddress : loc.addressLine1,
    );
  }
}

/// Shows a bottom sheet restricted to the user's saved locations, with an
/// "إضافة جديد" shortcut to create a new one. Returns null if dismissed
/// without a selection.
Future<LocationModel?> showLocationPickerSheet(
  BuildContext context, {
  required String token,
  String title = 'اختر الموقع',
}) async {
  await context.read<LocationProvider>().loadMyLocations(token);
  if (!context.mounted) return null;
  return showModalBottomSheet<LocationModel>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LocationPickerSheet(title: title),
  );
}

class _LocationPickerSheet extends StatelessWidget {
  final String title;
  const _LocationPickerSheet({required this.title});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addNew(context),
                    icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                    label: const Text('إضافة جديد'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer<LocationProvider>(
                builder: (_, provider, _) {
                  if (provider.isLoadingLocations) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.myLocations.isEmpty) {
                    return _EmptyLocations(onAdd: () => _addNew(context));
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: provider.myLocations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final loc = provider.myLocations[i];
                      return ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryFixed,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_iconFor(loc.locationType),
                              color: AppColors.primary, size: 20),
                        ),
                        title: Text(loc.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          loc.fullAddress.isNotEmpty
                              ? loc.fullAddress
                              : loc.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: loc.isPrimary
                            ? const Icon(Icons.star_rounded,
                                color: AppColors.primary, size: 18)
                            : const Icon(Icons.chevron_right_rounded,
                                color: Colors.grey),
                        onTap: () => Navigator.pop(context, loc),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNew(BuildContext context) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditLocationScreen()),
    );
    if (ok == true && context.mounted) {
      final provider = context.read<LocationProvider>();
      if (provider.myLocations.isNotEmpty) {
        Navigator.pop(context, provider.myLocations.first);
      }
    }
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case 'user_address':
        return Icons.home_rounded;
      case 'store':
        return Icons.store_rounded;
      case 'warehouse':
        return Icons.warehouse_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }
}

class _EmptyLocations extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyLocations({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_outlined,
              size: 52, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('لا توجد مواقع محفوظة',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('إضافة موقع جديد'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
