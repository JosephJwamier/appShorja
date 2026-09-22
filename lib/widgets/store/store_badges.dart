import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_colors.dart';

/// The badge catalogue: one SVG seal per kind (`assets/badges/{kind}.svg`) and
/// the Arabic name shown *beside* it — never inside the image, so the name
/// stays crisp at 24 px and can be translated without redrawing.
class StoreBadgeInfo {
  final String kind;
  final String name;
  final String meaning;
  const StoreBadgeInfo(this.kind, this.name, this.meaning);

  String get asset => 'assets/badges/$kind.svg';
}

const Map<String, StoreBadgeInfo> kStoreBadges = {
  'founder': StoreBadgeInfo('founder', 'مؤسِّس', 'من الخمسين الأوائل — عمولة صفر مدى الحياة'),
  'pioneer': StoreBadgeInfo('pioneer', 'رائد', 'من أوائل المتاجر — نصف العمولة مدى الحياة'),
  'certified': StoreBadgeInfo('certified', 'بائع معتمد', 'خرّيج مدرسة الشورجة'),
  'verified': StoreBadgeInfo('verified', 'موثَّق', 'هوية وهاتف موثّقان'),
  'bronze': StoreBadgeInfo('bronze', 'برونزي', 'مستوى الأداء'),
  'silver': StoreBadgeInfo('silver', 'فضّي', 'مستوى الأداء'),
  'gold': StoreBadgeInfo('gold', 'ذهبي', 'مستوى الأداء'),
  'diamond': StoreBadgeInfo('diamond', 'ماسي', 'مستوى الأداء'),
};

/// One seal, optionally with its name. Unknown kinds (a newer server) render
/// nothing rather than a broken image.
class StoreBadgeIcon extends StatelessWidget {
  final String kind;
  final double size;
  final bool withLabel;
  final TextStyle? labelStyle;

  const StoreBadgeIcon({
    super.key,
    required this.kind,
    this.size = 24,
    this.withLabel = false,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    final info = kStoreBadges[kind];
    if (info == null) return const SizedBox.shrink();
    final icon = SvgPicture.asset(info.asset, width: size, height: size,
        semanticsLabel: info.name);
    if (!withLabel) {
      return Tooltip(message: '${info.name} — ${info.meaning}', child: icon);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        SizedBox(width: size * 0.25),
        Text(
          info.name,
          style: labelStyle ??
              TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
        ),
      ],
    );
  }
}

/// The row of a store's badges, in the server's order. `compact` is the
/// 24 px form for product cards and chat headers (icons only, capped at
/// three so a card never grows); the default form labels the first badge
/// and keeps the rest as icons.
class StoreBadgesRow extends StatelessWidget {
  final List<String> kinds;
  final bool compact;
  final double size;

  const StoreBadgesRow({
    super.key,
    required this.kinds,
    this.compact = false,
    double? size,
  }) : size = size ?? (compact ? 20 : 28);

  @override
  Widget build(BuildContext context) {
    final shown = kinds.where(kStoreBadges.containsKey).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final visible = compact ? shown.take(3).toList() : shown;
    return Wrap(
      spacing: compact ? 4 : 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < visible.length; i++)
          StoreBadgeIcon(
            kind: visible[i],
            size: size,
            withLabel: !compact && i == 0,
          ),
      ],
    );
  }
}
