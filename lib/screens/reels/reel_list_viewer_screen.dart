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
import '../../utils/auth_gate.dart';
import '../../utils/share_helper.dart';
import '../../widgets/reels/reel_comments_sheet.dart';
import '../../widgets/reels/reel_overlay.dart';
import '../../widgets/reels/reel_video_pager.dart';
import '../product_details_screen.dart';
import '../store_profile_screen.dart';

/// أي قائمة ريلزات تخصّ المشاهد تملكها [ReelsProvider] — متجرٌ واحد، أو
/// مفضلته.
enum ReelViewerSource {
  /// ريلزات متجر واحد، تُفتح من تبويب «الريلز» في صفحته.
  store,

  /// الريلز المحفوظة، تُفتح من تبويب الريلز في شاشة المفضلة.
  saved,
}

/// A visitor watching a bounded list of reels full-screen, opened by tapping
/// a tile in a grid and starting on that tile.
///
/// The public [ReelOverlay], same as the feed — a visitor here is an
/// audience, not an owner, so they get like/comment/save/share/tagged-product.
/// What differs from [ReelsFeedScreen] is the list underneath: swiping stays
/// inside the list the visitor opened instead of wandering into the global
/// feed. Someone who opened a store and tapped its video asked for *that
/// store*, and someone who opened their bookmarks asked for *those* — a pager
/// that quietly leaves either loses them the thread.
///
/// Playback, the controller window and the mute preference all live in
/// [ReelVideoPager]; what this screen owns is the overlay's actions, view
/// tracking, and paging its list as the visitor nears its end.
class ReelListViewerScreen extends StatefulWidget {
  /// أي قائمة في [ReelsProvider] تُعرض. القائمة تُقرأ من المزوّد لا تُمرَّر
  /// هنا، فالشبكة التي فتحتنا والعارض يشتركان في مصدرٍ واحد: إلغاء الحفظ
  /// داخل العارض يُخرج البلاطة من الشبكة تحته بلا إعادة جلب.
  final ReelViewerSource source;

  /// يُعرض في شريط العنوان: اسم المتجر، أو «المحفوظة». وسمٌ لمكان المشاهد لا
  /// عنوانٌ للشاشة.
  final String title;

  final int initialIndex;

  const ReelListViewerScreen({
    super.key,
    required this.source,
    required this.title,
    required this.initialIndex,
  });

  @override
  State<ReelListViewerScreen> createState() => _ReelListViewerScreenState();
}

class _ReelListViewerScreenState extends State<ReelListViewerScreen> {
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

  // ---- القائمة المعروضة --------------------------------------------------

  bool get _isStore => widget.source == ReelViewerSource.store;

  List<Reel> _reelsOf(ReelsProvider p) =>
      _isStore ? p.storeReels : p.savedReels;

  bool _hasMoreIn(ReelsProvider p) =>
      _isStore ? p.storeReelsHasMore : p.savedReelsHasMore;

  bool _isLoadingMoreIn(ReelsProvider p) =>
      _isStore ? p.isLoadingMoreStoreReels : p.isLoadingMoreSavedReels;

  Future<void> _loadMore(ReelsProvider p, String token) => _isStore
      ? p.loadMoreStoreReels(accessToken: token)
      : p.loadMoreSavedReels(accessToken: token);

  // ---- تتبّع المشاهدة والترقيم ------------------------------------------

  void _onPageChanged(int index) {
    _scheduleViewRecord(index);

    final provider = context.read<ReelsProvider>();
    if (index >= _reelsOf(provider).length - 2 &&
        _hasMoreIn(provider) &&
        !_isLoadingMoreIn(provider)) {
      final token = context.read<AuthProvider>().accessToken;
      if (token != null) _loadMore(provider, token);
    }
  }

  /// نفس تأخير الخلاصة: المشاهدة تُسجَّل بعد ثانيتين من استقرار الريل، فلا
  /// يُحسب لمن مرّ عليه مسرعاً. والخادم يتجاهل مشاهدة صاحب الريل نفسه.
  void _scheduleViewRecord(int index) {
    _viewTimer?.cancel();
    final reels = _reelsOf(context.read<ReelsProvider>());
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
    // البوابة لا `return` صامتة: التطبيق مفتوح للضيوف، وقلبٌ لا يفعل شيئاً
    // عند الضغط يُقرأ كعطب لا كطلب حساب.
    if (!await requireAuth(context, reason: 'للإعجاب بهذا الريل')) return;
    if (!mounted) return;
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

  Future<void> _openComments(Reel reel) async {
    if (!await requireAuth(context, reason: 'للتعليق على هذا الريل')) return;
    if (!mounted) return;
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

  /// الحفظ في المفضلة. متفائل كالإعجاب، لكنه يُرجع الحالة عند الفشل: الإشارة
  /// المرجعية وعدٌ بأن الريل سيكون هناك لاحقاً، وعلامةٌ كاذبة تُكتشف عند فتح
  /// المفضلة أسوأ من رسالة الآن.
  Future<void> _toggleSave(Reel reel) async {
    if (!await requireAuth(context, reason: 'لحفظ هذا الريل في مفضلتك')) return;
    if (!mounted) return;
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    final provider = context.read<ReelsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final wasSaved = reel.isSavedByMe;

    provider.applySaveUpdate(reel.id, !wasSaved);
    try {
      final saved = await _reelService.setSaved(
          accessToken: token, reelId: reel.id, saved: !wasSaved);
      if (!mounted) return;
      // حالة الخادم لا حالتنا: حفظٌ مكرّر أو إزالةُ ما لم يُحفظ يردّان
      // الحقيقة النهائية، وقد تخالف ما افترضناه.
      if (saved != !wasSaved) provider.applySaveUpdate(reel.id, saved);
    } catch (e) {
      if (!mounted) return;
      provider.applySaveUpdate(reel.id, wasSaved);
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// صفحة المتجر: رجوعٌ إن كانت تحتنا مباشرة، ودفعٌ إن لم تكن.
  ///
  /// المحفوظة تجمع ريلزات متاجر لم يزُرها المشاهد، فالرجوع منها كان سيعيده
  /// إلى مفضلته بدل أن يُفتح المتجر الذي ضغط اسمه.
  Future<void> _openStore(Reel reel) async {
    if (_isStore) {
      Navigator.maybePop(context);
      return;
    }
    final token = context.read<AuthProvider>().accessToken ?? '';
    await _runCovered(() async {
      final store = await StoreService()
          .fetchStoreById(accessToken: token, storeId: reel.store.id);
      if (!mounted) return;
      if (store == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح المتجر')),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StoreProfileScreen(store: store)),
      );
    });
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
            final reels = _reelsOf(provider);
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
                    onSaveToggle: () => _toggleSave(info.reel),
                    onTagTap: info.reel.hasTaggedItem
                        ? () => _openTaggedItem(info.reel)
                        : null,
                    onStoreTap: () => _openStore(info.reel),
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
