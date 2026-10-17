import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/reel.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// The like/comment/tag/share + store-info chrome drawn over a reel's video,
/// styled after live_viewer_screen.dart's dark overlay (semi-transparent
/// black pills over full-bleed video) but laid out TikTok/Reels-style: a
/// vertical action column pinned to the screen's leading edge (RTL-aware via
/// PositionedDirectional) instead of live_viewer_screen's top-bar stat
/// chips, since a reels feed is one full-screen video per page rather than
/// a bounded video area with room for a top bar.
///
/// Purely presentational/controlled — all state (like toggling, comment
/// sheet, etc.) is owned by the parent screen, same convention as
/// LiveCommentsPanel.
class ReelOverlay extends StatelessWidget {
  final Reel reel;
  final VoidCallback onLikeToggle;
  final VoidCallback onCommentTap;
  final VoidCallback onShareTap;

  /// حفظ الريل في مفضلة المشاهد. اختياري: شاشة مشاهدة المحفوظات نفسها
  /// تمرّره، أمّا أي مُضيف لا يملك قائمة محفوظات فيُخفي الزرّ بتركه فارغاً
  /// بدل أن يعرض زرّاً لا يفعل شيئاً.
  final VoidCallback? onSaveToggle;
  final VoidCallback? onTagTap;
  final VoidCallback onStoreTap;
  final VoidCallback onMuteToggle;
  final bool isMuted;

  const ReelOverlay({
    super.key,
    required this.reel,
    required this.onLikeToggle,
    required this.onCommentTap,
    required this.onShareTap,
    this.onSaveToggle,
    this.onTagTap,
    required this.onStoreTap,
    required this.onMuteToggle,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // شريط علوي: كتم/تشغيل الصوت فقط — بقية عناصر التحكم أسفل الشاشة.
        PositionedDirectional(
          top: 8,
          end: 8,
          child: _CircleIconButton(
            icon: isMuted ? Icons.volume_off : Icons.volume_up,
            onTap: onMuteToggle,
          ),
        ),
        // عمود الإجراءات (لايك / تعليق / وسم / مشاركة) — الحافة البادئة
        // (يمين الشاشة في RTL) على طراز TikTok/Reels.
        PositionedDirectional(
          bottom: 90,
          end: 10,
          child: Column(
            children: [
              _ActionButton(
                icon: reel.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                iconColor: reel.isLikedByMe ? AppColors.error : Colors.white,
                label: '${reel.likesCount}',
                onTap: onLikeToggle,
              ),
              const SizedBox(height: 18),
              _ActionButton(
                icon: Icons.mode_comment_outlined,
                label: '${reel.commentsCount}',
                onTap: onCommentTap,
              ),
              if (reel.hasTaggedItem) ...[
                const SizedBox(height: 18),
                _ActionButton(
                  icon: Icons.shopping_bag_outlined,
                  label: 'المنتج',
                  onTap: onTagTap ?? () {},
                ),
              ],
              if (onSaveToggle != null) ...[
                const SizedBox(height: 18),
                _ActionButton(
                  // ممتلئ/فارغ لا تغيّر لون: الحفظ خاصّ، ولون الإعجاب
                  // الأحمر هنا كان سيجعل الزرّين يُقرآن كشيء واحد.
                  icon: reel.isSavedByMe
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  label: reel.isSavedByMe ? 'محفوظ' : 'حفظ',
                  onTap: onSaveToggle!,
                ),
              ],
              const SizedBox(height: 18),
              _ActionButton(
                icon: Icons.share_outlined,
                label: 'مشاركة',
                onTap: onShareTap,
              ),
            ],
          ),
        ),
        // معلومات المتجر + الوصف أسفل الشاشة، بعرض محدود كي لا يتداخل مع
        // عمود الإجراءات.
        PositionedDirectional(
          bottom: 16,
          start: 12,
          end: 74,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onStoreTap,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primaryContainer,
                        backgroundImage: reel.store.logoUrl != null
                            ? CachedNetworkImageProvider(reel.store.logoUrl!)
                            : null,
                        child: reel.store.logoUrl == null
                            ? const Icon(Icons.storefront, size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          reel.store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                if (reel.caption.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    reel.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
                if (reel.hasTaggedItem) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onTagTap,
                    child: Container(
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
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.iconColor = Colors.white,
    required this.label,
    required this.onTap,
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
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
