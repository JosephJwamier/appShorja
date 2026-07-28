import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product_review.dart';
import '../../providers/auth_provider.dart';
import '../../providers/review_provider.dart';
import '../../theme/app_colors.dart';
import 'add_edit_review_bottom_sheet.dart';
import 'review_card.dart';
import 'star_rating_widget.dart';

class ReviewListSection extends StatefulWidget {
  final int itemId;
  final int? ownerId;
  final double? averageRating;
  final int totalReviews;

  const ReviewListSection({
    super.key,
    required this.itemId,
    this.ownerId,
    this.averageRating,
    this.totalReviews = 0,
  });

  @override
  State<ReviewListSection> createState() => _ReviewListSectionState();
}

class _ReviewListSectionState extends State<ReviewListSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ReviewProvider>();
      provider.loadReviews();
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) provider.loadMyReview(auth.accessToken!);
    });
  }

  Future<void> _openAddReview() async {
    final reviewProvider = context.read<ReviewProvider>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: reviewProvider,
        child: const AddEditReviewBottomSheet(),
      ),
    );
  }

  Future<void> _openEditReview(ProductReview review) async {
    final reviewProvider = context.read<ReviewProvider>();
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: reviewProvider,
        child: AddEditReviewBottomSheet(existing: review),
      ),
    );
  }

  Future<void> _confirmDelete(ProductReview review) async {
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
          .read<ReviewProvider>()
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
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ReviewProvider>();
    final reviews = provider.reviews;
    final myReview = provider.myReview;
    final breakdown = provider.scoreBreakdown;

    final displayTotal = reviews.length > widget.totalReviews
        ? reviews.length
        : widget.totalReviews;
    final rating = widget.averageRating ?? 0.0;

    final isOwner = auth.user?.id == widget.ownerId;
    final canWrite = auth.isLoggedIn &&
        !isOwner &&
        myReview == null &&
        provider.myReviewChecked;

    final photoReviews =
        reviews.where((r) => r.imageUrl != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'التقييمات والمراجعات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              if (displayTotal > 0)
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'عرض الكل ‹',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Rating summary card ──────────────────────────────────
        if (displayTotal > 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SummaryCard(
              rating: rating,
              total: displayTotal,
              breakdown: breakdown,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Buyer photos ─────────────────────────────────────────
        if (photoReviews.isNotEmpty) ...[
          _BuyerPhotosSection(reviews: photoReviews),
          const SizedBox(height: 8),
        ],

        // ── Loading ──────────────────────────────────────────────
        if (provider.isLoadingReviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )

        // ── Empty state ──────────────────────────────────────────
        else if (reviews.isEmpty) ...[
          const SizedBox(height: 20),
          Center(
            child: Column(
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
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'كن أول من يقيّم هذا المنتج!',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ]

        // ── Review list ──────────────────────────────────────────
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (int i = 0; i < reviews.length; i++) ...[
                  ReviewCard(
                    key: ValueKey(reviews[i].id),
                    review: reviews[i],
                    currentUserId: auth.user?.id,
                    onEdit: () => _openEditReview(reviews[i]),
                    onDelete: () => _confirmDelete(reviews[i]),
                  ),
                  if (i < reviews.length - 1)
                    const Divider(
                      height: 1,
                      color: AppColors.surfaceContainer,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Write review button ──────────────────────────────────
        if (canWrite) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openAddReview,
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: const Text(
                  'اكتب تقييماً للمنتج',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Rating summary card ──────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double rating;
  final int total;
  final Map<int, int> breakdown;

  const _SummaryCard({
    required this.rating,
    required this.total,
    required this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
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
          // Right side (first child in RTL row): big number
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              StarDisplay(rating: rating, size: 16),
              const SizedBox(height: 5),
              Text(
                '$total تقييم',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 80, color: AppColors.surfaceContainer),
          const SizedBox(width: 16),
          // Left side (second child in RTL row): star bars
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [5, 4, 3, 2, 1].map((star) {
                final count = breakdown[star] ?? 0;
                final pct = total > 0 ? count / total : 0.0;
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
                            valueColor:
                                AlwaysStoppedAnimation(barColor),
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

// ── Buyer photos horizontal section ─────────────────────────────────────────

class _BuyerPhotosSection extends StatelessWidget {
  final List<ProductReview> reviews;

  const _BuyerPhotosSection({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'صور من المشترين',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: reviews.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final url = reviews[index].imageUrl!;
              return GestureDetector(
                onTap: () => showImageFullScreen(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    width: 86,
                    height: 86,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, error, _) => Container(
                      width: 86,
                      height: 86,
                      color: AppColors.surfaceContainerLow,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 1, color: AppColors.surfaceContainer),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
