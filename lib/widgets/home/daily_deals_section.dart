import 'package:flutter/material.dart';
import '../../models/filter_params.dart';
import '../../models/listing.dart';
import '../../screens/product_details_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

class DailyDealsSection extends StatelessWidget {
  final List<FixedListing> listings;
  final ValueChanged<FilterParams?>? onViewAll;

  const DailyDealsSection({super.key, required this.listings, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) return const SizedBox.shrink();

    // Prefer discounted items; fall back to any listing
    final discounted = listings
        .where((l) => (l.discountPercentage ?? 0) > 0 || l.item.isDailyDeal)
        .toList();
    final deals = (discounted.isNotEmpty ? discounted : listings).take(8).toList();

    // "View all" must match what's actually on screen: every card shown in
    // `deals` has to still appear in the "view all" results. The backend
    // only supports is_daily_deal and has_discount as separate AND-only
    // filters (no OR between them), so a single flag can only be used when
    // it's true for *every* shown card (`every`, not `any` — picking a flag
    // most cards share would silently drop the rest). If the preview is a
    // genuine mix of daily deals and plain discounts, or fell back to "any
    // listing" because nothing qualified, there's no single flag that keeps
    // every shown card — fall back to no filter (shows everything, which
    // still satisfies the invariant).
    final FilterParams? viewAllFilter = discounted.isEmpty
        ? null
        : deals.every((l) => l.item.isDailyDeal)
            ? const FilterParams(isDailyDeal: true)
            : deals.every((l) => (l.discountPercentage ?? 0) > 0)
                ? const FilterParams(hasDiscount: true)
                : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Gradient header ──────────────────────────────
              _BannerHeader(
                dealCount: deals.length,
                onViewAll: onViewAll == null
                    ? null
                    : () => onViewAll!(viewAllFilter),
              ),

              // ── Horizontal deal cards ────────────────────────
              ColoredBox(
                color: AppColors.surfaceContainerLowest,
                child: SizedBox(
                  height: 230,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    itemCount: deals.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _DealCard(listing: deals[i]),
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

// ─── Gradient header ────────────────────────────────────────────────────────

class _BannerHeader extends StatelessWidget {
  final int dealCount;
  final VoidCallback? onViewAll;
  const _BannerHeader({required this.dealCount, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryContainer],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: Row(
        children: [
          // Fire icon in a frosted circle
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_fire_department_rounded,
              color: Colors.amber,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),

          // Title + subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'صفقات اليوم',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$dealCount عرض حصري',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),

          const Spacer(),

          // "عرض الكل" pill button
          GestureDetector(
            onTap: onViewAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'عرض الكل',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Deal card ──────────────────────────────────────────────────────────────

class _DealCard extends StatelessWidget {
  final FixedListing listing;
  const _DealCard({required this.listing});

  double? get _originalPrice {
    if ((listing.originalPrice ?? 0) > 0) {
      return listing.originalPrice;
    }
    final pct = listing.discountPercentage;
    if (pct != null && pct > 0 && pct < 100) {
      return listing.price * 100 / (100 - pct);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = listing.item;
    final original = _originalPrice;
    final hasBadge = (listing.discountPercentage ?? 0) > 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailsScreen(listing: listing),
        ),
      ),
      child: Container(
        width: 128,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceContainerHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image + discount badge
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: item.firstImage != null
                        ? Image.network(
                            item.firstImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
                if (hasBadge)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _DiscountBadge(listing: listing),
                  ),
              ],
            ),

            // Text info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                        height: 1.3,
                      ),
                    ),
                    const Spacer(),
                    // Current (deal) price
                    Text(
                      formatIqd(listing.price),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryContainer,
                      ),
                    ),
                    // Original price (strikethrough)
                    if (original != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        formatIqd(original),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
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
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.outline,
        size: 32,
      ),
    );
  }
}

// ─── Discount badge ─────────────────────────────────────────────────────────

class _DiscountBadge extends StatelessWidget {
  final FixedListing listing;
  const _DiscountBadge({required this.listing});

  @override
  Widget build(BuildContext context) {
    final pct = listing.discountPercentage;
    if (pct == null || pct <= 0) return const SizedBox.shrink();
    final label = '-${pct.toStringAsFixed(0)}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4081),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
