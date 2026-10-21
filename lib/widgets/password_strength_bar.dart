import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/password_strength.dart';

/// شريط قوة كلمة المرور: أربع قطع، ووسم، وسطر يقول الخطوة التالية.
///
/// يختفي تماماً حين يكون الحقل فارغاً — لا يستقبل المستخدم نموذجاً
/// بتحذير أحمر قبل أن يكتب حرفاً.
class PasswordStrengthBar extends StatelessWidget {
  final PasswordVerdict verdict;

  const PasswordStrengthBar({super.key, required this.verdict});

  static const _segments = 4;

  @override
  Widget build(BuildContext context) {
    if (verdict.strength == PasswordStrength.none) {
      return const SizedBox.shrink();
    }

    final filled = switch (verdict.strength) {
      PasswordStrength.none => 0,
      PasswordStrength.weak => 1,
      PasswordStrength.fair => 2,
      PasswordStrength.good => 3,
      PasswordStrength.strong => 4,
    };
    final color = _colorFor(verdict.strength);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _segments; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < filled
                          ? color
                          : AppColors.outlineVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i != _segments - 1) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _labelFor(verdict.strength),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (verdict.hint != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verdict.hint!,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Color _colorFor(PasswordStrength s) => switch (s) {
        PasswordStrength.none || PasswordStrength.weak => AppColors.error,
        // كهرماني لا أخضر: «مقبولة» تمرّ على الخادم وليست توصية.
        PasswordStrength.fair => AppColors.gold,
        PasswordStrength.good || PasswordStrength.strong => AppColors.success,
      };

  static String _labelFor(PasswordStrength s) => switch (s) {
        PasswordStrength.none => '',
        PasswordStrength.weak => 'ضعيفة',
        PasswordStrength.fair => 'مقبولة',
        PasswordStrength.good => 'جيّدة',
        PasswordStrength.strong => 'قويّة',
      };
}
