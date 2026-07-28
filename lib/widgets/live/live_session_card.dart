import 'package:flutter/material.dart';
import '../../models/live_session.dart';
import '../../theme/app_colors.dart';

/// Discovery-grid card for a live session — thumbnail, LIVE badge, viewer
/// count, likes, and store name. Tap opens the viewer screen.
class LiveSessionCard extends StatelessWidget {
  final LiveSession session;
  final VoidCallback onTap;

  const LiveSessionCard({super.key, required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  session.thumbnailUrl != null
                      ? Image.network(
                          session.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _LiveBadge(isLive: session.isLive),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _Pill(
                      icon: Icons.visibility,
                      label: '${session.currentViewerCount}',
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: _Pill(
                      icon: session.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                      label: '${session.likesCount}',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    session.store.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceContainer,
        child: const Center(
          child: Icon(Icons.live_tv, size: 40, color: AppColors.onSurfaceVariant),
        ),
      );
}

class _LiveBadge extends StatelessWidget {
  final bool isLive;
  const _LiveBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    if (!isLive) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'مباشر',
        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
