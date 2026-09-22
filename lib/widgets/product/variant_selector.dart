import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../theme/app_colors.dart';

/// Chips for each option axis (colour, size…) so the buyer picks one exact
/// combination before reserving.
///
/// A value is disabled — not hidden — when no in-stock variant carries it
/// alongside the other picks so far. Hiding would make "L" vanish the moment
/// red-L sells out, which reads as the product never having come in L;
/// greying it says "not with what you've chosen", which is the truth.
///
/// Controlled: [selected] is owned by the parent, which also derives price,
/// stock and the reserve button's enabled state from it.
class VariantSelector extends StatelessWidget {
  final Product product;
  final Map<String, String> selected;
  final ValueChanged<Map<String, String>> onChanged;

  const VariantSelector({
    super.key,
    required this.product,
    required this.selected,
    required this.onChanged,
  });

  void _pick(String name, String value) {
    final next = Map<String, String>.from(selected);
    if (next[name] == value) {
      next.remove(name);
    } else {
      next[name] = value;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!product.hasOptions) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in product.options) ...[
          Row(
            children: [
              Text(
                option.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (selected[option.name] != null) ...[
                const SizedBox(width: 8),
                Text(
                  selected[option.name]!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in option.values)
                _ValueChip(
                  label: value,
                  isSelected: selected[option.name] == value,
                  isAvailable: product.isValueAvailable(
                    option.name,
                    value,
                    selected,
                  ),
                  onTap: () => _pick(option.name, value),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isAvailable;
  final VoidCallback onTap;

  const _ValueChip({
    required this.label,
    required this.isSelected,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final Color border;
    if (isSelected) {
      background = AppColors.primary;
      foreground = Colors.white;
      border = AppColors.primary;
    } else if (!isAvailable) {
      background = AppColors.surfaceContainerLow;
      foreground = AppColors.onSurfaceVariant.withValues(alpha: 0.45);
      border = AppColors.surfaceContainer;
    } else {
      background = AppColors.surfaceContainerLowest;
      foreground = AppColors.onSurface;
      border = AppColors.surfaceContainerHigh;
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        // Unavailable values stay tappable: picking one shows the buyer the
        // sold-out state directly instead of a dead chip they can't explore.
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: foreground,
              decoration: isAvailable ? null : TextDecoration.lineThrough,
            ),
          ),
        ),
      ),
    );
  }
}
