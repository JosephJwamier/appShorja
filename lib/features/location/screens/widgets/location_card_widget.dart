import 'package:flutter/material.dart';
import '../../models/location_model.dart';
import '../../../../theme/app_colors.dart';

class LocationCardWidget extends StatelessWidget {
  final LocationModel location;
  final VoidCallback? onTap;
  final VoidCallback? onSetPrimary;
  final VoidCallback? onDelete;

  const LocationCardWidget({
    super.key,
    required this.location,
    this.onTap,
    this.onSetPrimary,
    this.onDelete,
  });

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

  static String _labelFor(String type) {
    switch (type) {
      case 'user_address':
        return 'عنوان شخصي';
      case 'store':
        return 'متجر';
      case 'warehouse':
        return 'مستودع';
      default:
        return 'موقع';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: location.isPrimary
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Type icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryFixed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconFor(location.locationType),
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            location.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (location.isPrimary) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 3),
                                Text(
                                  'رئيسي',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      location.fullAddress,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _labelFor(location.locationType),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Actions
              Column(
                children: [
                  if (!location.isPrimary && onSetPrimary != null)
                    IconButton(
                      icon: const Icon(Icons.star_outline_rounded,
                          color: AppColors.primary),
                      tooltip: 'تعيين كرئيسي',
                      onPressed: onSetPrimary,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error),
                      tooltip: 'حذف',
                      onPressed: onDelete,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
