import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/listing.dart';
import '../providers/auth_provider.dart';
import '../providers/reels_provider.dart';
import '../services/item_service.dart';
import '../theme/app_colors.dart';
import '../widgets/home/home_product_card.dart';
import '../widgets/reels/reel_grid_tile.dart';
import 'reels/reel_list_viewer_screen.dart';

/// شاشة «المفضلة» — ما حفظه المستخدم بنفسه، على تبويبين: المنتجات والريلز.
///
/// تبويبان لا قائمة واحدة مختلطة: البطاقتان لا تشتركان في شيء (منتج ببطاقة
/// سعر عمودية، وريل بمصغّرة 9:16)، والترقيم على الخادم منفصل — نقطتان
/// مختلفتان وجدولان مختلفان. خلطهما في شبكة واحدة كان سيعني ترقيماً مزدوجاً
/// في قائمة واحدة، وهي أعقد مسألة من أن تُحلّ لأجل شكلٍ أقلّ وضوحاً.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.onSurface,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'المفضلة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            bottom: const TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurfaceVariant,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              unselectedLabelStyle: TextStyle(fontSize: 15),
              tabs: [
                Tab(text: 'المنتجات'),
                Tab(text: 'الريلز'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _FavoriteProductsTab(),
              _SavedReelsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// تبويب المنتجات المفضلة
// ══════════════════════════════════════════════════════════════

/// قائمة مرقّمة الصفحات بالمنتجات التي فضّلها المستخدم، مع إزالة أي منتج
/// مباشرة من البطاقة.
class _FavoriteProductsTab extends StatefulWidget {
  const _FavoriteProductsTab();

  @override
  State<_FavoriteProductsTab> createState() => _FavoriteProductsTabState();
}

class _FavoriteProductsTabState extends State<_FavoriteProductsTab>
    with AutomaticKeepAliveClientMixin {
  final _service = ItemService();
  final _scrollController = ScrollController();

  List<FixedListing> _listings = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchFavoriteListingsPaginated(
        accessToken: token,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _listings = result.listings;
        _hasMore = result.hasMore;
        _page = 1;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    final token = context.read<AuthProvider>().accessToken ?? '';
    setState(() => _isLoadingMore = true);
    try {
      final result = await _service.fetchFavoriteListingsPaginated(
        accessToken: token,
        page: _page + 1,
      );
      if (!mounted) return;
      setState(() {
        _listings = [..._listings, ...result.listings];
        _hasMore = result.hasMore;
        _page += 1;
      });
    } catch (_) {
      // فشل تحميل صفحة إضافية لا يمسح ما هو ظاهر بالفعل
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _removeFavorite(FixedListing listing) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final index = _listings.indexOf(listing);
    if (index == -1) return;
    setState(() => _listings.removeAt(index));
    try {
      await _service.setFavorite(
        accessToken: token,
        itemId: listing.item.id,
        favorited: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _listings.insert(index, listing));
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _buildBody(),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_isLoading) {
      return const [
        SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (_error != null && _listings.isEmpty) {
      return [
        SliverFillRemaining(child: _ErrorState(message: _error!, onRetry: _load)),
      ];
    }
    if (_listings.isEmpty) {
      return const [
        SliverFillRemaining(
          child: _EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'لا توجد منتجات في مفضلتك بعد',
            hint: 'اضغط على أيقونة القلب في أي منتج لإضافته هنا',
          ),
        ),
      ];
    }
    final cardWidth = (MediaQuery.sizeOf(context).width - 16 * 2 - 14) / 2;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: cardWidth + 150,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => HomeProductCard(
              listing: _listings[i],
              onRemoveFavorite: () => _removeFavorite(_listings[i]),
            ),
            childCount: _listings.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: _isLoadingMore
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ];
  }
}

// ══════════════════════════════════════════════════════════════
// تبويب الريلز المحفوظة
// ══════════════════════════════════════════════════════════════

/// شبكة مصغّرات لما حفظه المستخدم من ريلزات، الأحدث حفظاً أولاً، تُفتح
/// مشاهدةً ملء الشاشة عند الضغط.
///
/// اسم المتجر يُعرض على كل مربّع هنا بخلاف شبكة ملف المتجر: ريلزات المحفوظة
/// من متاجر مختلفة، ومصغّرةٌ بلا نسبة إلى أحد لا تُعرَّف.
class _SavedReelsTab extends StatefulWidget {
  const _SavedReelsTab();

  @override
  State<_SavedReelsTab> createState() => _SavedReelsTabState();
}

class _SavedReelsTabState extends State<_SavedReelsTab>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // صفّان تقريباً قبل النهاية — الصفحة التالية تصل قبل أن يبلغ القاع.
    if (position.pixels < position.maxScrollExtent - 400) return;
    final provider = context.read<ReelsProvider>();
    if (!provider.savedReelsHasMore || provider.isLoadingMoreSavedReels) return;
    final token = context.read<AuthProvider>().accessToken;
    if (token != null) provider.loadMoreSavedReels(accessToken: token);
  }

  Future<void> _refresh() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    await context.read<ReelsProvider>().loadSavedReels(accessToken: token);
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReelListViewerScreen(
          source: ReelViewerSource.saved,
          title: 'المحفوظة',
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<ReelsProvider>();
    final reels = provider.savedReels;

    if (provider.isLoadingSavedReels && reels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.savedReelsError != null && reels.isEmpty) {
      return _ErrorState(message: provider.savedReelsError!, onRetry: _refresh);
    }
    if (reels.isEmpty) {
      return const _EmptyState(
        icon: Icons.bookmark_border_rounded,
        title: 'لا توجد ريلزات محفوظة',
        hint: 'اضغط على علامة الحفظ في أي ريل ليظهر هنا',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: kReelTileAspectRatio,
        ),
        itemCount: reels.length,
        itemBuilder: (context, index) => ReelGridTile(
          reel: reels[index],
          // المحفوظة من متاجر مختلفة، ومصغّرةٌ بلا نسبةٍ إلى أحد لا تُعرَّف.
          showStoreName: true,
          onTap: () => _openViewer(index),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// حالات مشتركة بين التبويبين
// ══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.surfaceContainerHigh),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
