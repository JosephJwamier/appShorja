import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reel.dart';
import '../../providers/reels_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/reels/reel_video_pager.dart';

/// The owner watching their own reels, full-screen, swiping vertically —
/// opened by tapping a tile in [MyReelsScreen] and starting on that tile.
///
/// Deliberately not the public [ReelOverlay]: an owner doesn't need a like
/// button on their own video or a link to their own store. What they need is
/// how it's doing (views/likes/comments) and a way straight to editing or
/// deleting it, which is what the chrome here shows instead.
///
/// No view is recorded from this screen — and the backend wouldn't count one
/// anyway, since it ignores views from a reel's own store owner. The numbers
/// on screen stay a measure of real audience.
class MyReelViewerScreen extends StatefulWidget {
  final int initialIndex;

  /// Called with the reel the owner asked to act on; the caller (MyReelsScreen)
  /// owns the edit/delete flows so both entry points share one implementation.
  final Future<void> Function(Reel reel) onEdit;
  final Future<void> Function(Reel reel) onDelete;

  const MyReelViewerScreen({
    super.key,
    required this.initialIndex,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<MyReelViewerScreen> createState() => _MyReelViewerScreenState();
}

class _MyReelViewerScreenState extends State<MyReelViewerScreen> {
  /// يصير خطأً أثناء وجود شاشة التعديل أو حوار الحذف فوقنا، فيتوقّف الفيديو
  /// بدل أن يظلّ يعمل — ويُسمع — خلفها.
  bool _isActive = true;

  Future<void> _runCovered(Future<void> Function() action) async {
    setState(() => _isActive = false);
    await action();
    if (mounted) setState(() => _isActive = true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<ReelsProvider>(
          builder: (context, provider, _) {
            final reels = provider.myReels;
            // حذف آخر ريل من داخل هذه الشاشة يترك القائمة فارغة — نغلقها بدل
            // عرض شاشة سوداء بلا محتوى.
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
                  overlayBuilder: (context, info) => _OwnerOverlay(
                    reel: info.reel,
                    isMuted: info.isMuted,
                    onMuteToggle: info.onMuteToggle,
                    onEdit: () => _runCovered(() => widget.onEdit(info.reel)),
                    onDelete: () => _runCovered(() => widget.onDelete(info.reel)),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Owner-facing chrome over a reel: performance numbers instead of a like
/// button, and edit/delete instead of share/store links.
class _OwnerOverlay extends StatelessWidget {
  final Reel reel;
  final bool isMuted;
  final VoidCallback onMuteToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OwnerOverlay({
    required this.reel,
    required this.isMuted,
    required this.onMuteToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PositionedDirectional(
          top: 8,
          end: 8,
          child: _CircleButton(
            icon: isMuted ? Icons.volume_off : Icons.volume_up,
            onTap: onMuteToggle,
          ),
        ),
        PositionedDirectional(
          bottom: 100,
          end: 10,
          child: Column(
            children: [
              _CircleButton(icon: Icons.edit_outlined, onTap: onEdit, label: 'تعديل'),
              const SizedBox(height: 18),
              _CircleButton(
                icon: Icons.delete_forever,
                onTap: onDelete,
                label: 'حذف',
                iconColor: AppColors.error,
              ),
            ],
          ),
        ),
        PositionedDirectional(
          bottom: 20,
          start: 12,
          end: 78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _Stat(icon: Icons.visibility, value: reel.viewCount),
                  const SizedBox(width: 14),
                  _Stat(icon: Icons.favorite, value: reel.likesCount),
                  const SizedBox(width: 14),
                  _Stat(icon: Icons.mode_comment_outlined, value: reel.commentsCount),
                ],
              ),
              if (reel.caption.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  reel.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
              if (reel.hasTaggedItem) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag, size: 14, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          reel.item!.price != null
                              ? '${reel.item!.title} — ${formatIqd(reel.item!.price!)}'
                              : reel.item!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final int value;
  const _Stat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 15),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final Color iconColor;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
