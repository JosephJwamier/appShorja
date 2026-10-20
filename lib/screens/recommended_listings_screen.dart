import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/recommended_listings_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/home/home_product_card.dart';

/// "عرض الكل" screen for the home-page "مقترح لك" section — the full,
/// infinite-scroll version of the same personalized feed.
class RecommendedListingsScreen extends StatefulWidget {
  const RecommendedListingsScreen({super.key});

  @override
  State<RecommendedListingsScreen> createState() =>
      _RecommendedListingsScreenState();
}

class _RecommendedListingsScreenState
    extends State<RecommendedListingsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    final token = context.read<AuthProvider>().browseToken;
    await context.read<RecommendedListingsProvider>().reset(accessToken: token);
  }

  void _onScroll() {
    if (!mounted) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      context
          .read<RecommendedListingsProvider>()
          .loadMore(accessToken: context.read<AuthProvider>().browseToken);
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
          title: const Text('مقترح لك', style: TextStyle(fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Consumer<RecommendedListingsProvider>(
          builder: (ctx, prov, _) {
            if (prov.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (prov.errorMessage != null && prov.items.isEmpty) {
              return _buildError(prov.errorMessage!);
            }

            if (prov.isEmpty) {
              return const Center(
                child: Text(
                  'ما عدنا مقترحات لك بعد',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              );
            }

            final cardWidth = (MediaQuery.sizeOf(ctx).width - 16 * 2 - 12) / 2;
            return RefreshIndicator(
              onRefresh: _initialize,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => HomeProductCard(listing: prov.items[i]),
                        childCount: prov.items.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: cardWidth + 150,
                      ),
                    ),
                  ),
                  if (prov.isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.onSurface)),
          const SizedBox(height: 12),
          TextButton(onPressed: _initialize, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
