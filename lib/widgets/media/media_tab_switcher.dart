import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

const _switchDuration = Duration(milliseconds: 200);

/// المبدّل النصّي بين «ريلز» و«مباشر» أعلى `MediaHubScreen` — كلمتان بلا
/// حاوية ولا خلفية، على طراز Instagram/TikTok، مع مؤشّر سفلي قصير يظهر تحت
/// الكلمة المختارة.
///
/// عرضٌ بحت (controlled): لا يملك أي حالة، والاختيار يملكه المضيف — نفس عُرف
/// [ReelOverlay] و LiveCommentsPanel في هذا المشروع.
///
/// [onDark] يبدّل لوح الألوان بدل توحيد مظهر الشاشتين: أبيض (مع ظلّ نصّي
/// يضمن القراءة فوق أي لقطة فيديو) في وضع الريلز الأسود، وألوان السطح
/// المعتادة في وضع البث الفاتح — فيبقى لكل تبويب هويته البصرية الأصلية.
class MediaTabSwitcher extends StatelessWidget {
  /// ارتفاع الشريط الذي يشغله المبدّل. يستخدمه `LiveSessionsScreen` في وضع
  /// `embedded` لإزاحة محتواه أسفله بدل شريط التطبيق المحذوف.
  static const double height = 48;

  /// 0 = ريلز، 1 = مباشر.
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool onDark;

  const MediaTabSwitcher({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onDark,
  });

  @override
  Widget build(BuildContext context) {
    // المضيف يُبنى داخل MainShell (بلا Directionality صريح، أي LTR افتراضاً)،
    // لذا نفرض RTL هنا كي تأتي «ريلز» — وهي الافتراضية — يميناً.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SwitcherLabel(
            label: 'ريلز',
            selected: selectedIndex == 0,
            onDark: onDark,
            onTap: () => onSelected(0),
          ),
          _SwitcherLabel(
            label: 'مباشر',
            selected: selectedIndex == 1,
            onDark: onDark,
            onTap: () => onSelected(1),
          ),
        ],
      ),
    );
  }
}

class _SwitcherLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final bool onDark;
  final VoidCallback onTap;

  const _SwitcherLabel({
    required this.label,
    required this.selected,
    required this.onDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = onDark ? Colors.white : AppColors.onSurface;
    final idleColor = onDark ? Colors.white54 : AppColors.onSurfaceVariant;
    final indicatorColor = onDark ? Colors.white : AppColors.primary;

    // MaterialType.transparency: أقرب Material فوقنا هو جسم MainShell أسفل
    // الفيديو، فبدون هذه الطبقة يرتسم أثر النقر تحته ولا يُرى إطلاقاً.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        splashColor: onDark ? Colors.white24 : null,
        highlightColor: onDark ? Colors.white10 : null,
        child: Container(
          // 48×72 — فوق الحدّ الأدنى لمساحة اللمس (44×44)، فالنصّ وحده أصغر
          // بكثير من أن يكون هدفاً مريحاً.
          constraints: const BoxConstraints(
            minWidth: 72,
            minHeight: MediaTabSwitcher.height,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: _switchDuration,
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? activeColor : idleColor,
                  shadows: onDark
                      ? const [Shadow(color: Colors.black54, blurRadius: 4)]
                      : null,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: _switchDuration,
                curve: Curves.easeOut,
                height: 2,
                width: selected ? 22 : 0,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
