import 'package:flutter/material.dart';

import '../../models/reel.dart';
import '../../theme/app_colors.dart';
import '../app_network_image.dart';

/// بلاطة ريل في شبكة الزائر — الصورة المصغّرة وعدّاد المشاهدات.
///
/// بلا شارة حالة ولا زرّ ⋮، بخلاف بلاطة صاحب المتجر: الزائر لا يرى إلا
/// المنشور، ولا يملك عليه تعديلاً ولا حذفاً.
///
/// مشتركة بين شبكتين: تبويب «الريلز» في صفحة المتجر، وتبويب الريلز المحفوظة
/// في المفضلة. البلاطة صورة ساكنة لا مشغّل فيديو — الشبكة تُبنى كاملةً عند
/// فتح الشاشة، ومشغّلٌ لكل بلاطة كان سيُشغّل عشرة فيديوهات دفعةً واحدة
/// ويُسمعها.
class ReelGridTile extends StatelessWidget {
  final Reel reel;
  final VoidCallback onTap;

  /// اسم المتجر في أعلى البلاطة — لشبكة المحفوظة وحدها. ريلزاتها من متاجر
  /// مختلفة، ومصغّرةٌ بلا نسبةٍ إلى أحد لا تُعرَّف. شبكة صفحة المتجر لا
  /// تحتاجه: كل ما فيها لمتجر واحد، واسمه فوق الشاشة أصلاً.
  final bool showStoreName;

  const ReelGridTile({
    super.key,
    required this.reel,
    required this.onTap,
    this.showStoreName = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
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
            if (showStoreName && reel.store.name.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    reel.store.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            // تدرّج أسفل البلاطة: الصور المصغّرة الفاتحة كانت تبتلع الرقم.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                    const SizedBox(width: 2),
                    Text(
                      '${reel.viewCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    if (reel.hasTaggedItem) ...[
                      const Spacer(),
                      const Icon(Icons.shopping_bag,
                          color: AppColors.gold, size: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نسبة بلاطة الريل — تُستعمل في كل شبكة ريلزات كي تُقرأ الشبكة كشريط
/// ريلزات لا كصور منتجات مربّعة.
const double kReelTileAspectRatio = 0.6;
