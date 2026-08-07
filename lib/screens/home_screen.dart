import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/home_items_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/following_provider.dart';
import '../providers/recommended_items_provider.dart';
import '../theme/app_colors.dart';
import '../utils/refreshable_tab.dart';
import '../widgets/home/home_search_bar.dart';
import '../widgets/home/categories_row.dart';
import '../widgets/home/categories_bottom_sheet.dart';
import '../widgets/home/home_product_card.dart';
import '../widgets/home/daily_deals_section.dart';
import '../widgets/home/following_stores_section.dart';
import '../widgets/home/recommended_section.dart';
import '../features/location/screens/map_screen.dart';
import '../models/filter_params.dart';
import 'category_browse_screen.dart';
import 'category_products_screen.dart';
import 'deals_screen.dart';
import 'filter_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> implements RefreshableTab {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    await Future.wait([
      context.read<CategoryProvider>().loadCategories(accessToken: token),
      context.read<HomeItemsProvider>().reset(accessToken: token),
      context.read<FollowingProvider>().load(accessToken: token),
      context.read<RecommendedItemsProvider>().load(accessToken: token),
    ]);
  }

  void _onScroll() {
    if (!mounted) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      final token = context.read<AuthProvider>().accessToken;
      if (token != null) {
        context.read<HomeItemsProvider>().loadMore(accessToken: token);
      }
    }
  }

  void _onCategorySelected(int? categoryId) {
    if (categoryId == null) {
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) return;
      context.read<CategoryProvider>().selectCategory(null);
      context.read<HomeItemsProvider>().reset(
        accessToken: token,
        categoryId: null,
        isCategoryReset: true,
      );
      return;
    }

    // بدل التصفية في مكانها: الضغط على تصنيف يفتح شاشة تصفّح مستقلة.
    // التصنيفات الرئيسية تعرض تصنيفاتها الفرعية؛ أمّا تصنيف فرعي (مثل الشرائح
    // المختلطة في هذا الصف) فيذهب مباشرة لقائمة منتجاته.
    final categories = context.read<CategoryProvider>().categories;
    final matches = categories.where((c) => c.id == categoryId);
    final category = matches.isNotEmpty ? matches.first : null;

    if (category != null && !category.isRoot) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryProductsScreen(
            categoryId: category.id,
            title: category.displayName,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryBrowseScreen(initialCategoryId: categoryId),
      ),
    );
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: query.trim()),
      ),
    );
  }

  @override
  Future<void> refreshTab() => _onRefresh();

  Future<void> _onRefresh() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    await Future.wait([
      context.read<HomeItemsProvider>().reset(accessToken: token),
      context.read<FollowingProvider>().load(accessToken: token),
      context.read<RecommendedItemsProvider>().load(accessToken: token),
    ]);
  }

  Future<void> _openFilterScreen() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    final currentFilters = context.read<HomeItemsProvider>().filters;

    final result = await Navigator.push<FilterParams>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FilterScreen(initialFilters: currentFilters, accessToken: token),
      ),
    );

    if (result != null && mounted) {
      context.read<CategoryProvider>().selectCategory(result.categoryId);
      context.read<HomeItemsProvider>().reset(
        accessToken: token,
        filters: result,
      );
    }
  }

  void _onViewAllDeals(FilterParams? filters) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DealsScreen(filters: filters)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppColors.primary,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // AppBar: لوگو + سلة + إشعارات
                SliverToBoxAdapter(child: _buildAppBar()),

                // SearchBar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: HomeSearchBar(
                        controller: _searchController,
                        onSubmit: _onSearch,
                      ),
                    ),
                  ),
                ),

                // صف الفئات الديناميكي
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Consumer<CategoryProvider>(
                      builder: (ctx, catProv, _) {
                        if (catProv.isLoading) {
                          return const SizedBox(
                            height: 90,
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        // البنر يعرض التصنيفات الرئيسية فقط (وليس كل
                        // التصنيفات الفرعية المسطّحة) — الضغط على أيّ منها
                        // يفتح شاشة تصفّح التصنيفات.
                        final rootCategories =
                            catProv.categories.where((c) => c.isRoot).toList();
                        if (rootCategories.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return CategoriesRow(
                          categories: rootCategories,
                          selectedCategoryId: catProv.selectedCategoryId,
                          onCategorySelected: _onCategorySelected,
                          onShowAll: () => CategoriesBottomSheet.show(
                            ctx,
                            categories: rootCategories,
                            selectedCategoryId: catProv.selectedCategoryId,
                            onSelect: _onCategorySelected,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // بانر قريب منك
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _NearMeBanner(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MapScreen()),
                      ),
                    ),
                  ),
                ),

                // بانر صفقات اليوم
                Consumer<HomeItemsProvider>(
                  builder: (_, prov, _) {
                    if (prov.items.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverToBoxAdapter(
                      child: DailyDealsSection(
                        listings: prov.items,
                        onViewAll: _onViewAllDeals,
                      ),
                    );
                  },
                ),

                // قسم "مقترح لك" حسب اهتمامات المستخدم
                const SliverToBoxAdapter(child: RecommendedSection()),

                // قسم منتجات المتاجر التي تتابعها (بعد صفقات اليوم وقبل كل المنتجات)
                const SliverToBoxAdapter(child: FollowingStoresSection()),

                // عنوان قسم المنتجات
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'المنتجات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ),

                // شبكة المنتجات
                Consumer<HomeItemsProvider>(
                  builder: (ctx, prov, _) {
                    if (prov.isLoading) {
                      return const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (prov.errorMessage != null && prov.items.isEmpty) {
                      return SliverFillRemaining(
                        child: _buildError(prov.errorMessage!),
                      );
                    }

                    if (prov.isEmpty) {
                      return const SliverFillRemaining(
                        child: Center(
                          child: Text(
                            'لا توجد منتجات بعد',
                            style: TextStyle(color: AppColors.onSurfaceVariant),
                          ),
                        ),
                      );
                    }

                    final cardWidth =
                        (MediaQuery.sizeOf(ctx).width - 16 * 2 - 12) / 2;
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => HomeProductCard(listing: prov.items[i]),
                          childCount: prov.items.length,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          // ارتفاع البطاقة = عرض الصورة المربّعة + مساحة ثابتة
                          // للنص، بدل نسبة تكبر مع عرض الشاشة (كانت تترك فراغاً
                          // كبيراً أسفل البطاقة على الشاشات العريضة).
                          mainAxisExtent: cardWidth + 150,
                        ),
                      ),
                    );
                  },
                ),

                // مؤشر تحميل المزيد
                Consumer<HomeItemsProvider>(
                  builder: (_, prov, _) {
                    if (!prov.isLoadingMore) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  },
                ),

                // padding سفلي
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          // زر الخريطة
          IconButton(
            icon: const Icon(Icons.map_rounded, color: AppColors.primary),
            tooltip: 'الخريطة',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapScreen()),
            ),
          ),
          const Spacer(),
          // لوگو
          const Text(
            'الشورجة',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // زر الفلتر مع badge عند وجود فلاتر نشطة
          Consumer<HomeItemsProvider>(
            builder: (_, prov, _) => Badge(
              isLabelVisible: prov.filters.hasActiveFilters,
              backgroundColor: AppColors.primaryContainer,
              textColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.tune_rounded, color: AppColors.primary),
                tooltip: 'التصفية',
                onPressed: _openFilterScreen,
              ),
            ),
          ),
          // الإشعارات مع badge
          Consumer<NotificationsProvider>(
            builder: (ctx, notif, _) => Badge(
              isLabelVisible: notif.unreadCount > 0,
              label: Text('${notif.unreadCount}'),
              backgroundColor: AppColors.primary,
              textColor: Colors.white,
              child: IconButton(
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.primary,
                ),
                onPressed: () {
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  notif.markAllRead();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _onRefresh,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

class _NearMeBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _NearMeBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryContainer],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'قريب منك',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'اكتشف المنتجات والمتاجر في منطقتك',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'استكشف',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
