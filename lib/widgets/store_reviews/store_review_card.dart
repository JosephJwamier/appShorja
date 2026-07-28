import 'package:flutter/material.dart';
import '../../models/store_review.dart';
import '../../theme/app_colors.dart';
import '../reviews/star_rating_widget.dart';

class StoreReviewCard extends StatefulWidget {
  final StoreReview review;
  final int? currentUserId;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const StoreReviewCard({
    super.key,
    required this.review,
    this.currentUserId,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<StoreReviewCard> createState() => _StoreReviewCardState();
}

class _StoreReviewCardState extends State<StoreReviewCard> {
  bool _expanded = false;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 365) return 'منذ ${diff.inDays ~/ 365} سنة';
    if (diff.inDays >= 30) return 'منذ ${diff.inDays ~/ 30} شهر';
    if (diff.inDays >= 7) return 'منذ ${diff.inDays ~/ 7} أسبوع';
    if (diff.inDays >= 1) return 'منذ ${diff.inDays} يوم';
    if (diff.inHours >= 1) return 'منذ ${diff.inHours} ساعة';
    if (diff.inMinutes >= 1) return 'منذ ${diff.inMinutes} دقيقة';
    return 'الآن';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final isOwner = widget.currentUserId == r.reviewer.id;
    final initial =
        r.reviewer.username.isNotEmpty ? r.reviewer.username[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceContainerHigh,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.reviewer.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    StarDisplay(rating: r.score.toDouble(), size: 14),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _relativeTime(r.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (isOwner) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ActionIcon(
                          icon: Icons.edit_outlined,
                          color: AppColors.secondary,
                          onTap: widget.onEdit,
                        ),
                        const SizedBox(width: 4),
                        _ActionIcon(
                          icon: Icons.delete_outline,
                          color: AppColors.error,
                          onTap: widget.onDelete,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                r.comment,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            if (r.comment.length > 120)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _expanded ? 'عرض أقل ▲' : 'عرض المزيد ▼',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionIcon({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
}
