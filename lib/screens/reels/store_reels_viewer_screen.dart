import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reel.dart';
import '../../models/store.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reels_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/item_service.dart';
import '../../services/reel_service.dart';
import '../../utils/share_helper.dart';
import '../../widgets/reels/reel_comments_sheet.dart';
import '../../widgets/reels/reel_overlay.dart';
import '../../widgets/reels/reel_video_pager.dart';
import '../product_details_screen.dart';

/// A visitor watching one store's reels full-screen, opened by tapping a
/// tile in the reels tab of that store's profile and starting on that tile.
///
/// The public [ReelOverlay], same as the feed — a visitor here is an
/// audience, not an owner, so they get like/comment/share/tagged-product.
/// What differs from [ReelsFeedScreen] is the list underneath: swiping
/// stays inside this store's reels instead of wandering into other stores'.
/// Someone who opened a store and tapped its video asked for *that store*,
/// and a pager that quietly leaves it loses them the thread.
///
/// Playback, the controller window and the mute preference all live in
/// [ReelVideoPager]; what this screen owns is the overlay's actions, view
/// tracking, and paging the store's list as the visitor nears its end.
class StoreReelsViewerScreen extends StatefulWidget {
  final Store store;
  final int initialIndex;

  const StoreReelsViewerScreen({
    super.key,
    required this.store,
    required this.initialIndex,
  });

  @override
  State<StoreReelsViewerScreen> createState() => _StoreReelsViewerScreenState();
}

class _StoreReelsViewerScreenState extends State<StoreReelsViewerScreen> {
  final _reelService = ReelService();
  Timer? _viewTimer;

  /// يصير خطأً أثناء وجود شاشة أخرى فوقنا (منتج موسوم، تعليقات) فيتوقّف
  /// الفيديو بدل أن يظلّ يعمل — ويُسمع — خلفها.
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    // أول ريل لا يمرّ بـ onPageChanged، فمشاهدته تُجدول هنا.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scheduleViewRecord(widget.initialIndex),
    );
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    super.dispose();
  }

  Future<void> _runCovered(Future<void> Function() action) async {
    setState(() => _isActive = false);
    await action();
    if (mounted) setState(() => _isActive = true);
  }

  // ---- تتبّع المشاهدة والترقيم ------------------------------------------

  void _onPageChanged(int index) {
    _scheduleViewRecord(index);

    final provider = context.read<ReelsProvider>();
    if (index >= provider.storeReels.length - 2 &&
        provider.storeReelsHasMore &&
        !provider.isLoadingMoreStoreReels) {
      final token = context.read<AuthProvider>().accessToken;
      if (token != null) provider.loadMoreStoreReels(accessToken: token);
    }
  }

  /// نفس تأخير الخلاصة: المشاهدة تُسجَّل بعد ثانيتين من استقرار الريل، فلا
  /// يُحسب لمن مرّ عليه مسرعاً. والخادم يتجاهل مشاهدة صاحب الريل نفسه.
  void _scheduleViewRecord(int index) {
    _viewTimer?.cancel();
    final reels = context.read<ReelsProvider>().storeReels;
    if (index < 0 || index >= reels.length) return;
    final reelId = reels[index].id;
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    _viewTimer = Timer(const Duration(seconds: 2), () {
      _reelService.recordView(accessToken: token, reelId: reelId);
    });
  }

  // ---- actions ----------------------------------------------------------

  Future<void> _toggleLike(Reel reel) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    final provider = context.read<ReelsProvider>();
    final wasLiked = reel.isLikedByMe;

    provider.applyLikeUpdate(
      reel.id,
      !wasLiked,
      reel.likesCount + (wasLiked ? -1 : 1),
    );
    final result = wasLiked
        ? await _reelService.unlikeReel(accessToken: token, reelId: reel.id)
        : await _reelService.likeReel(accessToken: token, reelId: reel.id);
    if (!mounted) return;
    if (result.success) {
      provider.applyLikeUpdate(reel.id, !wasLiked, result.likesCount);
    } else {
      provider.applyLikeUpdate(reel.id, wasLiked, reel.likesCount);
    }
  }

  void _openComments(Reel reel) {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    final isOwner = context.read<StoreProvider>().myStore?.id == reel.store.id;
    showReelCommentsSheet(
      context,
      reel: reel,
      accessToken: token,
      currentUserId: auth.user?.id,
      isStoreOwner: isOwner,
      onCommentPosted: () =>
          context.read<ReelsProvider>().applyCommentPosted(reel.id),
    );
  }

  void _shareReel(Reel reel) {
    shareLink(
      context,
      text: reel.caption.isNotEmpty
          ? '${reel.caption}\n${reel.videoUrl}'
          : reel.videoUrl,
      subject: 'ريل من ${reel.store.name}',
    );
  }

  Future<void> _openTaggedItem(Reel reel) async {
    final item = reel.item;
    final token = context.read<AuthProvider>().accessToken;
    if (item == null || token == null) return;
    final listing = await ItemService().fetchListingByItemId(
      accessToken: token,
      itemId: item.id,
    );
    if (!mounted) return;
    if (listing != null) {
      await _runCovered(() async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(listing: listing),
          ),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا المنتج غير متوفر حالياً')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<ReelsProvider>(
          builder: (context, provider, _) {
            final reels = provider.storeReels;
            // القائمة قد تفرغ تحتنا (صاحب المتجر يحذف ريلاً من شاشة أخرى،
            // أو غادر المستخدم المتجر فمُسحت) — نغلق بدل شاشة سوداء.
            if (reels.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.maybePop(context);
              });
              return const SizedBox.shrink();
            }

            return Stack(
              children: [
                ReelVideoPager(
                  reels: reels,
                  initialIndex: widget.initialIndex.clamp(0, reels.length - 1),
                  isActive: _isActive,
                  onPageChanged: _onPageChanged,
                  overlayBuilder: (context, info) => ReelOverlay(
                    reel: info.reel,
                    isMuted: info.isMuted,
                    onMuteToggle: info.onMuteToggle,
                    onLikeToggle: () => _toggleLike(info.reel),
                    onCommentTap: () => _openComments(info.reel),
                    onShareTap: () => _shareReel(info.reel),
                    onTagTap: info.reel.hasTaggedItem
                        ? () => _openTaggedItem(info.reel)
                        : null,
                    // الرجوع لا الدفع: صفحة هذا المتجر هي ما تحتنا مباشرة،
                    // ودفع نسخة ثانية منها كان سيبني كومةً من الصفحة نفسها
                    // يخرج منها المستخدم ضغطةً ضغطة.
                    onStoreTap: () => Navigator.maybePop(context),
                  ),
                ),
                const _BackButton(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// العارض يُدفع فوق صفحة المتجر، وفيديو ملء الشاشة لا يترك حافةً واضحة
/// للرجوع — فزرّ صريح، كما في عارض صاحب المتجر.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            color: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.maybePop(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
