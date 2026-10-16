import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reel.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reels_provider.dart';
import '../../services/reel_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_network_image.dart';
import 'create_reel_screen.dart';
import 'edit_reel_screen.dart';
import 'my_reel_viewer_screen.dart';
import '../../widgets/reels/reel_comments_sheet.dart';

/// The store owner's reel management screen — everything they've posted, at
/// any status (pending_upload/published/failed/archived), and the only place
/// a reel can be created, edited, or deleted from.
///
/// Posting lives here rather than on the feed: the feed is a viewing surface
/// (full-bleed video, no chrome to spare) and a store owner scrolling it is
/// consuming, not publishing. Putting "new reel" next to "my reels" also
/// matches "متجري" → "منتجاتي" elsewhere in the app. Reached from a small
/// icon on ReelsFeedScreen's top bar, shown once the user has a store.
class MyReelsScreen extends StatefulWidget {
  /// يُفتح هذا الريل فور التحميل، وتُفتح تعليقاته.
  ///
  /// مدخل إشعار التعليق. يمرّ من هنا لا من العارض مباشرة لأن دوالّ
  /// التعديل والحذف تعيش هنا — فتوجيه الإشعار إلى العارض كان سيعني
  /// نسخة ثانية منها.
  final int? openCommentsForReelId;

  /// التعليق الذي جاء منه الإشعار — يُظلَّل ويُمرَّر إليه.
  final int? highlightCommentId;

  const MyReelsScreen({
    super.key,
    this.openCommentsForReelId,
    this.highlightCommentId,
  });

  @override
  State<MyReelsScreen> createState() => _MyReelsScreenState();
}

class _MyReelsScreenState extends State<MyReelsScreen> {
  final _service = ReelService();

  /// Which reel currently has a delete in flight — an id rather than a bare
  /// flag so only that tile shows a spinner, instead of freezing the grid.
  int? _deletingReelId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (mounted) await _openRequestedComments();
    });
  }

  /// يفتح الريل المطلوب وتعليقاته — بعد التحميل لأن الفهرس يُحسب من
  /// القائمة المحمّلة.
  Future<void> _openRequestedComments() async {
    final reelId = widget.openCommentsForReelId;
    if (reelId == null) return;

    final reels = context.read<ReelsProvider>().myReels;
    final index = reels.indexWhere((r) => r.id == reelId);
    // الريل قد يكون حُذف أو أُرشف بين وصول الإشعار وفتحه؛ تُترك الشبكة
    // معروضة بدل شاشة خطأ عن شيء لم يعد موجوداً.
    if (index < 0) return;

    await _openViewer(index);
    if (!mounted) return;

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    await showReelCommentsSheet(
      context,
      reel: reels[index],
      accessToken: token,
      currentUserId: context.read<AuthProvider>().user?.id,
      isStoreOwner: true,
      highlightCommentId: widget.highlightCommentId,
    );
  }

  Future<void> _load() {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return Future.value();
    return context.read<ReelsProvider>().loadMyReels(accessToken: token);
  }

  Future<void> _openCreateReel() async {
    final created = await Navigator.push<Reel>(
      context,
      MaterialPageRoute(builder: (_) => const CreateReelScreen()),
    );
    if (created != null && mounted) {
      context.read<ReelsProvider>().prependPublishedReel(created);
    }
  }

  /// Full-screen playback starting on the tapped tile. The edit/delete flows
  /// are passed down rather than reimplemented there, so both the grid and
  /// the viewer act on a reel identically — one confirmation dialog, one
  /// provider update.
  Future<void> _openViewer(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyReelViewerScreen(
          initialIndex: index,
          onEdit: _openEdit,
          onDelete: _confirmDelete,
        ),
      ),
    );
  }

  Future<void> _openReelActions(Reel reel) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
                title: const Text('تعديل الوصف والمنتج'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: AppColors.error),
                title: const Text('حذف نهائي',
                    style: TextStyle(color: AppColors.error)),
                subtitle: const Text('يُمسح الفيديو من الخوادم ولا يمكن التراجع'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'edit') {
      await _openEdit(reel);
    } else if (action == 'delete') {
      await _confirmDelete(reel);
    }
  }

  Future<void> _openEdit(Reel reel) async {
    final updated = await Navigator.push<Reel>(
      context,
      MaterialPageRoute(builder: (_) => EditReelScreen(reel: reel)),
    );
    if (updated != null && mounted) {
      context.read<ReelsProvider>().applyReelUpdate(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ التعديلات')),
      );
    }
  }

  Future<void> _confirmDelete(Reel reel) async {
    // Two-step on purpose: this is irreversible and takes the video off the
    // storage servers, not just out of the feed. The typed-out consequence
    // in the body is what separates it from an ordinary archive dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الريل نهائياً؟'),
          content: const Text(
            'سيُحذف الفيديو والصورة المصغّرة من خوادم التخزين نهائياً، مع كل '
            'الإعجابات والتعليقات المرتبطة به.\n\nلا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تراجع'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف نهائي',
                  style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    setState(() => _deletingReelId = reel.id);
    final result = await _service.deleteReel(accessToken: token, reelId: reel.id);
    if (!mounted) return;
    setState(() => _deletingReelId = null);

    if (result.success) {
      context.read<ReelsProvider>().removeReelLocally(reel.id);
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  String _statusLabel(String status) => switch (status) {
        'published' => 'منشور',
        'pending_upload' => 'قيد الرفع',
        'failed' => 'فشل',
        'archived' => 'مؤرشف',
        _ => status,
      };

  Color _statusColor(String status) => switch (status) {
        'published' => AppColors.success,
        'pending_upload' => AppColors.gold,
        'failed' => AppColors.error,
        _ => AppColors.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('ريلزاتي')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'myReelsCreateFab',
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('ريل جديد', style: TextStyle(color: Colors.white)),
          onPressed: _openCreateReel,
        ),
        body: Consumer<ReelsProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingMyReels && provider.myReels.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.myReelsError != null && provider.myReels.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(provider.myReelsError!),
                    const SizedBox(height: 8),
                    ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                  ],
                ),
              );
            }
            if (provider.myReels.isEmpty) {
              return _buildEmptyState();
            }
            return RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                // Bottom padding clears the FAB so the last row isn't stuck
                // underneath it.
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.6,
                ),
                itemCount: provider.myReels.length,
                itemBuilder: (context, index) {
                  final reel = provider.myReels[index];
                  return _ReelTile(
                    reel: reel,
                    statusLabel: _statusLabel(reel.status),
                    statusColor: _statusColor(reel.status),
                    isDeleting: _deletingReelId == reel.id,
                    // النقر يشغّل، وزرّ ⋮ وحده يفتح التعديل/الحذف — وهو ما
                    // يتوقّعه المستخدم من شبكة ريلز.
                    onTap: () => _openViewer(index),
                    onActions: () => _openReelActions(reel),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      // A ListView (not a Center) so RefreshIndicator still has something
      // scrollable to pull on when the grid is empty.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        const Icon(Icons.video_library_outlined,
            size: 56, color: AppColors.onSurfaceVariant),
        const SizedBox(height: 12),
        const Text(
          'لم تنشر أي ريل بعد',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _openCreateReel,
            icon: const Icon(Icons.add),
            label: const Text('انشر أول ريل'),
          ),
        ),
      ],
    );
  }
}

class _ReelTile extends StatelessWidget {
  final Reel reel;
  final String statusLabel;
  final Color statusColor;
  final bool isDeleting;
  final VoidCallback onTap;
  final VoidCallback onActions;

  const _ReelTile({
    required this.reel,
    required this.statusLabel,
    required this.statusColor,
    required this.isDeleting,
    required this.onTap,
    required this.onActions,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isDeleting ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            reel.thumbnailUrl != null
                ? AppNetworkImage(reel.thumbnailUrl!, fit: BoxFit.cover)
                : Container(
                    color: AppColors.surfaceContainer,
                    child: const Icon(Icons.videocam_outlined,
                        color: AppColors.onSurfaceVariant),
                  ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: statusColor, borderRadius: BorderRadius.circular(6)),
                child: Text(statusLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
            // Its own hit target, not just an icon: tapping the tile plays
            // the reel, so edit/delete needs somewhere distinct to live.
            Positioned(
              top: 0,
              left: 0,
              child: GestureDetector(
                onTap: isDeleting ? null : onActions,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white, size: 16),
                ),
              ),
            ),
            // مؤشّر تشغيل صغير يوضّح أن البطاقة نفسها قابلة للتشغيل.
            const Center(
              child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 30),
            ),
            if (reel.hasTaggedItem)
              const Positioned(
                bottom: 22,
                right: 4,
                child: Icon(Icons.shopping_bag, color: AppColors.gold, size: 12),
              ),
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Row(
                children: [
                  const Icon(Icons.favorite, color: Colors.white, size: 11),
                  const SizedBox(width: 2),
                  Text('${reel.likesCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10)),
                  const SizedBox(width: 8),
                  const Icon(Icons.visibility, color: Colors.white, size: 11),
                  const SizedBox(width: 2),
                  Text('${reel.viewCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
            if (isDeleting)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
