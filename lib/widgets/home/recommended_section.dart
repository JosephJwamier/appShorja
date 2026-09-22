import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/recommended_items_provider.dart';
import '../../screens/recommended_listings_screen.dart';
import '../../theme/app_colors.dart';
import 'home_product_card.dart';

/// Home-screen section: products picked for the current user based on their
/// interests (onboarding picks + purchases/follows), same visual language as
/// [DailyDealsSection] but backed by [RecommendedItemsProvider].
class RecommendedSection extends StatelessWidget {
  const RecommendedSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RecommendedItemsProvider>(
      builder: (context, prov, _) {
        final items = prov.items;
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'مقترح لك',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RecommendedListingsScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'عرض الكل',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Icon(Icons.chevron_left,
                              size: 16, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 288,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => SizedBox(
                  width: 150,
                  child: HomeProductCard(listing: items[i]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
