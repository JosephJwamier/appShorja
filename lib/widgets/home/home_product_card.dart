import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import '../../models/listing.dart';
import '../../screens/product_details_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../store/store_badges.dart';

class HomeProductCard extends StatelessWidget {
  final FixedListing listing;
  /// When set, shows a filled-heart button over the image that calls this
  /// instead of navigating — used by the favorites screen to remove an item
  /// without opening its details first. Null everywhere else.
  final VoidCallback? onRemoveFavorite;

  const HomeProductCard({super.key, required this.listing, this.onRemoveFavorite});

  @override
  Widget build(BuildContext context) {
    final item = listing.item;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(listing: listing)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceContainer),
          boxShadow: [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صورة المنتج مع الـ badges و FAB
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: item.firstImage != null
                        ? AppNetworkImage(
                            item.firstImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
                // badge الخصم
                if ((listing.discountPercentage ?? 0) > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _DiscountBadge(
                      text:
                          '-${listing.discountPercentage!.toStringAsFixed(0)}%',
                    ),
                  ),
                if (onRemoveFavorite != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: GestureDetector(
                      onTap: onRemoveFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite,
                            size: 16, color: AppColors.error),
                      ),
                    ),
                  ),
              ],
            ),
            // تفاصيل المنتج
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // شارات المتجر — قبل الاسم كي تُقرأ مع نظرة واحدة
                  if (item.owner.storeBadges.isNotEmpty) ...[
                    StoreBadgesRow(
                      kinds: item.owner.storeBadges,
                      compact: true,
                      size: 16,
                    ),
                    const SizedBox(height: 4),
                  ],
                  // الاسم
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (item.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // مبيع + تقييم
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${listing.item.soldCount ?? 0} مباع',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if ((listing.item.totalReviews ?? 0) > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFF7C948)),
                        Text(
                          ' ${(listing.item.rating ?? 0).toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // السعر
                  Text(
                    formatIqd(listing.price),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryContainer,
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

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceContainer,
      child: const Icon(Icons.image_outlined,
          color: AppColors.outline, size: 40),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  final String text;
  const _DiscountBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4081),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
