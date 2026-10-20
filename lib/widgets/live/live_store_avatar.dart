import 'package:flutter/material.dart';
import '../../models/store.dart';
import '../../screens/live/live_viewer_screen.dart';
import '../../theme/app_colors.dart';

/// Wraps any store avatar with a pulsing "live" halo + a "مباشر" badge
/// whenever [store] currently has an active live session, and opens the
/// viewer on tap. Renders [avatar] completely untouched otherwise.
///
/// Keeps the exact same [size]x[size] footprint as a plain avatar in both
/// cases — the ring/halo/badge paint slightly outside that box (Stack with
/// clipBehavior.none) rather than growing it, so this can drop into any
/// existing avatar call site without touching surrounding layout code.
class LiveStoreAvatar extends StatefulWidget {
  final Store store;
  final Widget avatar;
  final double size;
  final double badgeFontSize;

  const LiveStoreAvatar({
    super.key,
    required this.store,
    required this.avatar,
    required this.size,
    this.badgeFontSize = 9,
  });

  @override
  State<LiveStoreAvatar> createState() => _LiveStoreAvatarState();
}

class _LiveStoreAvatarState extends State<LiveStoreAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _openLive(BuildContext context, int sessionId) {
    // عبر البوابة: هذه الحلقة تظهر في الصفحة الرئيسية وفي ملف المتجر،
    // وكلاهما مفتوح للضيوف الآن.
    openLiveViewer(context, sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.store.liveSessionId;
    if (sessionId == null) return widget.avatar;

    final size = widget.size;
    final ringSize = size + 8;
    final innerWhiteSize = size + 4;

    return GestureDetector(
      onTap: () => _openLive(context, sessionId),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // هالة نابضة تتمدّد وتخفت باستمرار خلف الحلقة لتلفت الانتباه دون
            // أن تحجب صورة المتجر.
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return Transform.scale(
                  scale: 1.0 + t * 0.5,
                  child: Container(
                    width: ringSize,
                    height: ringSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.error
                          .withValues(alpha: (1.0 - t).clamp(0.0, 1.0) * 0.45),
                    ),
                  ),
                );
              },
            ),
            // حلقة تدرّجية ثابتة حول الصورة، بأسلوب حلقات "البث المباشر".
            Container(
              width: ringSize,
              height: ringSize,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    AppColors.error,
                    AppColors.primaryContainer,
                    AppColors.gold,
                    AppColors.error,
                  ],
                ),
              ),
              child: Container(
                width: innerWhiteSize,
                height: innerWhiteSize,
                alignment: Alignment.center,
                decoration:
                    const BoxDecoration(shape: BoxShape.circle, color: AppColors.surface),
                child: ClipOval(child: widget.avatar),
              ),
            ),
            Positioned(
              bottom: -6,
              child: _LiveBadge(fontSize: widget.badgeFontSize),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final double fontSize;
  const _LiveBadge({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          ),
          const SizedBox(width: 3),
          Text(
            'مباشر',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
