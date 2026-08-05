import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/store.dart';
import '../../providers/auth_provider.dart';
import '../../providers/following_provider.dart';
import '../../screens/following_stores_screen.dart';
import '../../screens/product_details_screen.dart';
import '../../screens/store_profile_screen.dart';
import '../../services/item_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../live/live_store_avatar.dart';

/// Home-screen section: stores the user follows (as a circular avatar row,
/// like the "متابعاتك" row in the design) followed by a preview row of the
/// latest products from those stores.
class FollowingStoresSection extends StatelessWidget {
  const FollowingStoresSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FollowingProvider>(
      builder: (context, prov, _) {
        final groups = prov.groups;
        if (groups.isEmpty) return const SizedBox.shrink();

        final products = <(Product, Store)>[
          for (final g in groups)
            for (final p in g.items) (p, g.store),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'من متابعاتك',
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
                        builder: (_) => const FollowingStoresScreen(),
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

            // ── صف المتاجر (صورة دائرية + اسم المتجر) ────────────────
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, i) =>
                    _StoreAvatarItem(store: groups[i].store),
              ),
            ),

            if (products.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Text(
                  'جديد من المتاجر التي تتابعها',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _FollowingProductCard(
                    product: products[i].$1,
                    store: products[i].$2,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─── صورة دائرية للمتجر + اسمه ──────────────────────────────────────────────

class _StoreAvatarItem extends StatelessWidget {
  final Store store;
  const _StoreAvatarItem({required this.store});

  @override
  Widget build(BuildContext context) {
    final logo = store.fullLogoUrl;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoreProfileScreen(store: store)),
      ),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            LiveStoreAvatar(
              store: store,
              size: 64,
              avatar: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainer,
                  border: Border.all(color: AppColors.surfaceContainerHigh, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: logo != null
                    ? AppNetworkImage(
                        logo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.storefront,
                          color: AppColors.onSurfaceVariant,
                        ),
                      )
                    : const Icon(Icons.storefront, color: AppColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              store.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── بطاقة منتج من متجر متابَع ──────────────────────────────────────────────

class _FollowingProductCard extends StatelessWidget {
  final Product product;
  final Store store;
  const _FollowingProductCard({required this.product, required this.store});

  Future<void> _openProduct(BuildContext context) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final listing = await ItemService()
          .fetchListingByItemId(accessToken: token, itemId: product.id);
      navigator.pop();
      if (listing != null) {
        navigator.push(
          MaterialPageRoute(builder: (_) => ProductDetailsScreen(listing: listing)),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('لا يوجد عرض سعر ثابت لهذا المنتج بعد')),
        );
      }
    } catch (_) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر فتح تفاصيل المنتج')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = product.firstImage;
    return GestureDetector(
      onTap: () => _openProduct(context),
      child: Container(
        width: 140,
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: image != null
                      ? AppNetworkImage(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _StoreBadge(name: store.name),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (product.price != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatIqd(product.price!),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.inventory_2_outlined,
            color: AppColors.onSurfaceVariant),
      );
}

class _StoreBadge extends StatelessWidget {
  final String name;
  const _StoreBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      constraints: const BoxConstraints(maxWidth: 100),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront, size: 10, color: AppColors.tertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
