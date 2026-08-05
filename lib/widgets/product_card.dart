import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import '../models/listing.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../screens/product_details_screen.dart';

class ProductCard extends StatelessWidget {
  final FixedListing listing;
  const ProductCard({super.key, required this.listing});

  ({Color color, String label})? _statusInfo(String status) {
    switch (status) {
      case 'active':
        return (color: AppColors.success, label: 'متاح');
      case 'sold':
        return (color: AppColors.error, label: 'نفد');
      case 'draft':
        return (color: Colors.grey, label: 'مسوّدة');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = listing.item;
    final status = _statusInfo(item.status);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(listing: listing),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceContainer),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصورة + الشارة
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: item.firstImage != null
                        ? AppNetworkImage(
                            item.firstImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.surfaceContainer,
                              child: const Icon(Icons.broken_image,
                                  color: AppColors.outline),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceContainer,
                            child: const Icon(Icons.image,
                                color: AppColors.outline),
                          ),
                  ),
                ),
                if (status != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: status.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // المحتوى
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // اسم البائع
                  Row(
                    children: [
                      const Icon(Icons.storefront,
                          size: 13, color: AppColors.tertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.owner.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // العنوان
                  SizedBox(
                    height: 36,
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // السعر
                  RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      text: '${formatNum(listing.price)} ',
                      style: const TextStyle(
                        color: AppColors.primaryContainer,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                      children: const [
                        TextSpan(
                          text: 'IQD',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}