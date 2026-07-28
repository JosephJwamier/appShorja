import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/followed_store_group.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../providers/auth_provider.dart';
import '../services/item_service.dart';
import '../services/store_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'product_details_screen.dart';
import 'store_profile_screen.dart';

/// شاشة "متاجر تتابعها" — كل المتاجر التي يتابعها المستخدم مع معاينة منتجاتها.
class FollowingStoresScreen extends StatefulWidget {
  const FollowingStoresScreen({super.key});

  @override
  State<FollowingStoresScreen> createState() => _FollowingStoresScreenState();
}

class _FollowingStoresScreenState extends State<FollowingStoresScreen> {
  late Future<List<FollowedStoreGroup>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FollowedStoreGroup>> _load() {
    final token = context.read<AuthProvider>().accessToken ?? '';
    return StoreService().fetchFollowingStores(accessToken: token);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    // الشاشة مدفوعة فوق MainShell (الذي يُبنى بدون Directionality صريح، أي
    // LTR افتراضيًا) — لذا نغلّف شريط العنوان والمحتوى بـ RTL هنا صراحةً
    // ليتطابق ترتيب العناصر مع تصميم عربي سليم.
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.onSurface,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'متاجر تتابعها',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<List<FollowedStoreGroup>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _refresh);
            }
            final groups = snapshot.data ?? [];
            if (groups.isEmpty) {
              return _EmptyState(onRefresh: _refresh);
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                      height: 32, color: AppColors.surfaceContainerHigh),
                ),
                itemBuilder: (context, i) => _StoreSection(group: groups[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── قسم متجر واحد ──────────────────────────────────────────────────────────

class _StoreSection extends StatelessWidget {
  final FollowedStoreGroup group;
  const _StoreSection({required this.group});

  void _openStore(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoreProfileScreen(store: group.store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = group.store;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _openStore(context),
                child: Row(
                  children: [
                    _StoreAvatar(store: store),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          store.name,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${store.followersCount} متابع',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            Container(
                              width: 3,
                              height: 3,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 6),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            Text(
                              '${store.totalActiveItems} منتج',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _openStore(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'زيارة المتجر',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    Icon(Icons.chevron_left, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 222,
          child: group.items.isEmpty
              ? const _NoItemsPlaceholder()
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: group.items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _ProductMiniCard(product: group.items[i]),
                ),
        ),
      ],
    );
  }
}

class _StoreAvatar extends StatelessWidget {
  final Store store;
  const _StoreAvatar({required this.store});

  @override
  Widget build(BuildContext context) {
    final logo = store.fullLogoUrl;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceContainer,
        border: Border.all(color: AppColors.surfaceContainerHigh, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: logo != null
          ? Image.network(
              logo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront,
                color: AppColors.onSurfaceVariant,
              ),
            )
          : const Icon(Icons.storefront, color: AppColors.onSurfaceVariant),
    );
  }
}

class _NoItemsPlaceholder extends StatelessWidget {
  const _NoItemsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceContainer),
        ),
        child: const Text(
          'لا توجد منتجات معروضة حالياً',
          style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── بطاقة منتج مصغّرة ──────────────────────────────────────────────────────

class _ProductMiniCard extends StatelessWidget {
  final Product product;
  const _ProductMiniCard({required this.product});

  Future<void> _open(BuildContext context) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final listing = await ItemService().fetchListingByItemId(
        accessToken: token,
        itemId: product.id,
      );
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
    final img = product.firstImage;
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        width: 148,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceContainer),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: img != null
                  ? Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(),
                    )
                  : _fallback(),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (product.price != null)
                    Text(
                      formatIqd(product.price!),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
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

  Widget _fallback() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.inventory_2_outlined, color: AppColors.onSurfaceVariant),
      );
}

// ─── حالات فارغة / خطأ ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_outlined, size: 56, color: AppColors.onSurfaceVariant),
                      SizedBox(height: 14),
                      Text(
                        'لا تتابع أي متجر بعد',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'تابع متاجرك المفضّلة ليظهر أحدث منتجاتها هنا',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          const Text(
            'تعذّر تحميل المتاجر المتابَعة',
            style: TextStyle(color: AppColors.onSurface),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
