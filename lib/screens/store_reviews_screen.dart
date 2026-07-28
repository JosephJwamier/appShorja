import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store.dart';
import '../models/store_review.dart';
import '../providers/auth_provider.dart';
import '../providers/store_review_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/reviews/star_rating_widget.dart';
import '../widgets/store_reviews/add_edit_store_review_bottom_sheet.dart';
import '../widgets/store_reviews/store_review_card.dart';

class StoreReviewsScreen extends StatelessWidget {
  final Store store;
  const StoreReviewsScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StoreReviewProvider(store.id),
      child: _StoreReviewsBody(store: store),
    );
  }
}

class _StoreReviewsBody extends StatefulWidget {
  final Store store;
  const _StoreReviewsBody({required this.store});

  @override
  State<_StoreReviewsBody> createState() => _StoreReviewsBodyState();
}

class _StoreReviewsBodyState extends State<_StoreReviewsBody> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<StoreReviewProvider>();
      provider.loadReviews();
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) provider.loadMyReview(auth.accessToken!);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<StoreReviewProvider>().loadMore();
    }
  }

  Future<void> _openAddReview() async {
    final provider = context.read<StoreReviewProvider>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: provider,
        child: const AddEditStoreReviewBottomSheet(),
      ),
    );
  }

  Future<void> _openEditReview(StoreReview review) async {
    final provider = context.read<StoreReviewProvider>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: provider,
        child: AddEditStoreReviewBottomSheet(existing: review),
      ),
    );
  }

  Future<void> _confirmDelete(StoreReview review) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف التقييم'),
          content: const Text('هل أنت متأكد من حذف تقييمك؟ لا يمكن التراجع.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    try {
      await context
          .read<StoreReviewProvider>()
          .deleteReview(token: token, reviewId: review.id);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg == '403' ? 'غير مسموح بحذف هذا التقييم' : msg),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<StoreReviewProvider>();
    final isOwnStore = auth.user?.id == store.user.id;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          foregroundColor: AppColors.onSurface,
          title: const Text(
            'تقييمات المتجر',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _RatingSummaryCard(store: store, provider: provider),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.loadReviews,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (auth.isLoggedIn && !isOwnStore)
                      _MyReviewBanner(
                        myReview: provider.myReview,
                        checked: provider.myReviewChecked,
                        onWrite: _openAddReview,
                        onEdit: () => _openEditReview(provider.myReview!),
                        onDelete: () => _confirmDelete(provider.myReview!),
                      ),
                    Text(
                      'جميع التقييمات (${provider.totalCount})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const Divider(height: 24, color: AppColors.surfaceContainer),
                    if (provider.isLoadingReviews)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary),
                        ),
                      )
                    else if (provider.error != null)
                      _ErrorState(
                          message: provider.error!, onRetry: provider.loadReviews)
                    else if (provider.reviews.isEmpty)
                      const _EmptyReviewsState()
                    else
                      for (int i = 0; i < provider.reviews.length; i++) ...[
                        StoreReviewCard(
                          key: ValueKey(provider.reviews[i].id),
                          review: provider.reviews[i],
                          currentUserId: auth.user?.id,
                          onEdit: () => _openEditReview(provider.reviews[i]),
                          onDelete: () => _confirmDelete(provider.reviews[i]),
                        ),
                        if (i < provider.reviews.length - 1)
                          const Divider(
                              height: 1, color: AppColors.surfaceContainer),
                      ],
                    if (provider.isLoadingMore)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// بطاقة ملخّص التقييم (ثابتة أعلى الشاشة)
// ══════════════════════════════════════════════════════════════
class _RatingSummaryCard extends StatelessWidget {
  final Store store;
  final StoreReviewProvider provider;
  const _RatingSummaryCard({required this.store, required this.provider});

  @override
  Widget build(BuildContext context) {
    final breakdown = provider.scoreBreakdown;
    final loadedTotal = provider.reviews.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                store.rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              StarDisplay(rating: store.rating, size: 16),
              const SizedBox(height: 5),
              Text(
                'مبني على ${provider.totalCount} تقييم',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 80, color: AppColors.surfaceContainer),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [5, 4, 3, 2, 1].map((star) {
                final count = breakdown[star] ?? 0;
                final pct = loadedTotal > 0 ? count / loadedTotal : 0.0;
                final barColor = star == 5
                    ? AppColors.primary
                    : star == 4
                        ? AppColors.primaryContainer
                        : AppColors.surfaceContainerHigh;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    children: [
                      Text(
                        '$star',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.star_rounded,
                          size: 11, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 7,
                            backgroundColor: AppColors.surfaceContainerHigh,
                            valueColor: AlwaysStoppedAnimation(barColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// شريط «تقييمي» (كتابة / تعديل / حذف)
// ══════════════════════════════════════════════════════════════
class _MyReviewBanner extends StatelessWidget {
  final StoreReview? myReview;
  final bool checked;
  final VoidCallback onWrite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MyReviewBanner({
    required this.myReview,
    required this.checked,
    required this.onWrite,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (!checked) return const SizedBox.shrink();

    if (myReview == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'شاركنا تجربتك مع هذا المتجر',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onWrite,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              child: const Text('اكتب تقييماً',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final r = myReview!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('تقييمك',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface)),
              const SizedBox(width: 8),
              StarDisplay(rating: r.score.toDouble(), size: 15),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              r.comment,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('تعديل'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('حذف'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}

class _EmptyReviewsState extends StatelessWidget {
  const _EmptyReviewsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.rate_review_outlined,
                  size: 34, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            const Text(
              'لا توجد تقييمات بعد',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            const Text('كن أول من يقيّم هذا المتجر!',
                style:
                    TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
