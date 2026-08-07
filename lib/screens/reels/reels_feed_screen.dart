import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reel.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reels_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/item_service.dart';
import '../../services/reel_service.dart';
import '../../services/store_service.dart';
import '../../utils/refreshable_tab.dart';
import '../../utils/share_helper.dart';
import '../../utils/visibility_aware_tab.dart';
import '../../widgets/reels/reel_comments_sheet.dart';
import '../../widgets/reels/reel_overlay.dart';
import '../../widgets/reels/reel_video_pager.dart';
import '../product_details_screen.dart';
import '../store_profile_screen.dart';
import 'my_reels_screen.dart';

/// Public TikTok/Reels-style feed. Video playback, the controller window and
/// the mute preference all live in [ReelVideoPager]; what's left here is what
/// makes this screen the *public feed* specifically: the like/comment/share
/// overlay, view tracking, pagination, and the way into the owner's own
/// management screen.
///
/// View tracking: fires ~2s after a reel becomes the active page (a debounce
/// — deliberately chosen over firing immediately on page-change, so a user
/// quickly flicking past several reels doesn't spam `/view/` for videos they
/// never actually watched). The backend ignores a view from the reel's own
/// store owner, so an owner scrolling past their own reel doesn't inflate it.
class ReelsFeedScreen extends StatefulWidget {
  /// `false` عندما تعيش هذه الشاشة داخل `MediaHubScreen`: المضيف هو من يقرّر
  /// متى تصبح مرئية عبر [VisibilityAwareTab]. بدون ذلك يبدأ الفيديو بالعمل
  /// فور إقلاع التطبيق — لأن `MainShell` يبني كل تبويباته دفعةً واحدة —
  /// بينما المستخدم ما زال على تبويب آخر.
  final bool startVisible;

  const ReelsFeedScreen({super.key, this.startVisible = true});

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen>
    implements RefreshableTab, VisibilityAwareTab {
  final _reelService = ReelService();
  Timer? _viewTimer;

  /// الشاشة معروضة فعلاً للمستخدم. تُمرَّر إلى [ReelVideoPager] الذي يوقف
  /// التشغيل متى صارت خطأً، فلا يعمل أي فيديو خلف تبويب آخر أو تحت شاشة
  /// مدفوعة.
  late bool _isTabVisible = widget.startVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    await context.read<ReelsProvider>().loadFeed(accessToken: token);
    if (!mounted) return;
    context.read<StoreProvider>().loadMyStore(accessToken: token);
  }

  @override
  Future<void> refreshTab() async => _load();

  @override
  void onTabHidden() {
    if (!_isTabVisible) return;
    // المؤقّت يسجّل مشاهدة بعد ثانيتين — لا نسجّل مشاهدة لريل غادره المستخدم.
    _viewTimer?.cancel();
    setState(() => _isTabVisible = false);
  }

  @override
  void onTabVisible() {
    if (_isTabVisible) return;
    setState(() => _isTabVisible = true);
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    super.dispose();
  }

  // ---- تتبّع المشاهدة والترقيم ------------------------------------------

  void _onPageChanged(int index) {
    _scheduleViewRecord(index);

    final provider = context.read<ReelsProvider>();
    if (index >= provider.reels.length - 2 &&
        provider.hasMore &&
        !provider.isLoadingMore) {
      final token = context.read<AuthProvider>().accessToken;
      if (token != null) provider.loadMore(accessToken: token);
    }
  }

  void _scheduleViewRecord(int index) {
    _viewTimer?.cancel();
    final reels = context.read<ReelsProvider>().reels;
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

    provider.applyLikeUpdate(reel.id, !wasLiked, reel.likesCount + (wasLiked ? -1 : 1));
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
      onCommentPosted: () => context.read<ReelsProvider>().applyCommentPosted(reel.id),
    );
  }

  void _shareReel(Reel reel) {
    shareLink(
      context,
      text: reel.caption.isNotEmpty ? '${reel.caption}\n${reel.videoUrl}' : reel.videoUrl,
      subject: 'ريل من ${reel.store.name}',
    );
  }

  Future<void> _openTaggedItem(Reel reel) async {
    final item = reel.item;
    final token = context.read<AuthProvider>().accessToken;
    if (item == null || token == null) return;
    final listing = await ItemService()
        .fetchListingByItemId(accessToken: token, itemId: item.id);
    if (!mounted) return;
    if (listing != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailsScreen(listing: listing)),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('هذا المنتج غير متوفر حالياً')));
    }
  }

  Future<void> _openStore(Reel reel) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    final store = await StoreService().fetchStoreById(accessToken: token, storeId: reel.store.id);
    if (!mounted || store == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => StoreProfileScreen(store: store)));
  }

  /// Opens the owner's management screen — where reels are created, edited
  /// and deleted. Bracketed with the visibility hooks because a pushed route
  /// covers this screen without unmounting it: without them the reel keeps
  /// playing, and talking, behind it.
  Future<void> _openMyReels() async {
    onTabHidden();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyReelsScreen()),
    );
    if (mounted) onTabVisible();
  }

  @override
  Widget build(BuildContext context) {
    final hasStore = context.watch<StoreProvider>().myStore != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        // No create-FAB here on purpose: posting lives in MyReelsScreen
        // alongside editing and deleting, and the feed stays a pure viewing
        // surface. The top-bar entry below is the way in.
        body: Consumer<ReelsProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && provider.reels.isEmpty) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            if (provider.errorMessage != null && provider.reels.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white70, size: 40),
                      const SizedBox(height: 8),
                      Text(provider.errorMessage!, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ],
                  ),
                ),
              );
            }
            if (provider.reels.isEmpty) {
              return Stack(
                children: [
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_collection_outlined, size: 56, color: Colors.white54),
                        SizedBox(height: 12),
                        Text('لا توجد ريلزات بعد', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  _buildTopBar(hasStore),
                ],
              );
            }
            return Stack(
              children: [
                ReelVideoPager(
                  reels: provider.reels,
                  isActive: _isTabVisible,
                  onPageChanged: _onPageChanged,
                  overlayBuilder: (context, info) => ReelOverlay(
                    reel: info.reel,
                    isMuted: info.isMuted,
                    onMuteToggle: info.onMuteToggle,
                    onLikeToggle: () => _toggleLike(info.reel),
                    onCommentTap: () => _openComments(info.reel),
                    onShareTap: () => _shareReel(info.reel),
                    onTagTap:
                        info.reel.hasTaggedItem ? () => _openTaggedItem(info.reel) : null,
                    onStoreTap: () => _openStore(info.reel),
                  ),
                ),
                _buildTopBar(hasStore),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(bool hasStore) {
    if (!hasStore) return const SizedBox.shrink();
    // A labelled pill rather than a bare icon: this is now the only way into
    // posting a reel (the create-FAB used to sit on this screen), so it has
    // to read as an entry point, not as a decorative glyph.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: GestureDetector(
            onTap: _openMyReels,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_library_outlined, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text('ريلزاتي',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
