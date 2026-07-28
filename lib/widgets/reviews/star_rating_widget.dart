import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Read-only star display supporting half-star from a decimal value.
class StarDisplay extends StatelessWidget {
  final double rating;
  final double size;

  const StarDisplay({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final threshold = i + 1;
        IconData icon;
        if (rating >= threshold) {
          icon = Icons.star_rounded;
        } else if (rating >= threshold - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, size: size, color: AppColors.gold);
      }),
    );
  }
}

/// Interactive 5-star picker – tapping a star sets the score.
class StarSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final double size;

  const StarSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final star = i + 1;
        return GestureDetector(
          onTap: () => onChanged(star),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              star <= selected
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: size,
              color: AppColors.gold,
            ),
          ),
        );
      }),
    );
  }
}
