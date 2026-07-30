import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/filter_params.dart';
import '../models/listing.dart';
import '../providers/auth_provider.dart';
import '../services/item_service.dart';
import '../theme/app_colors.dart';
import '../widgets/home/home_product_card.dart';

/// شاشة مستقلة تعرض كل منتجات تصنيف (أو تصنيف فرعي) معيّن بشبكة مرقّمة
/// الصفحات — تُفتح عند الضغط على بطاقة تصنيف فرعي في [CategoryBrowseScreen].
class CategoryProductsScreen extends StatefulWidget {
  final int categoryId;
  final String title;

  const CategoryProductsScreen({
    super.key,
    required this.categoryId,
    required this.title,
  });

  @override
  State<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final _service = ItemService();
  final _scrollController = ScrollController();

  List<FixedListing> _listings = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  FilterParams get _filters => FilterParams(categoryId: widget.categoryId);

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
      final result = await _service.fetchFixedListingsPaginated(
        accessToken: token,
        page: 1,
        filters: _filters,
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
      final result = await _service.fetchFixedListingsPaginated(
        accessToken: token,
        page: _page + 1,
        filters: _filters,
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          centerTitle: true,
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: _buildBody(),
          ),
        ),
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
      return const [SliverFillRemaining(child: _EmptyState())];
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
            (context, i) => HomeProductCard(listing: _listings[i]),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.surfaceContainerHigh,
            ),
            const SizedBox(height: 14),
            const Text(
              'لا توجد منتجات في هذا التصنيف بعد',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
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
