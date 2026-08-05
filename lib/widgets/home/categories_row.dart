import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import '../../models/category.dart';
import '../../theme/app_colors.dart';

class CategoriesRow extends StatelessWidget {
  final List<Category> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategorySelected;
  final VoidCallback onShowAll;

  const CategoriesRow({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 8, left: 16),
              itemCount: categories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _CategoryCircle(
                    label: 'الكل',
                    icon: Icons.favorite,
                    iconColor: AppColors.primary,
                    isSelected: selectedCategoryId == null,
                    onTap: () => onCategorySelected(null),
                  );
                }
                final cat = categories[index - 1];
                return _CategoryCircle(
                  label: cat.displayName,
                  iconUrl: cat.iconUrl,
                  iconCode: cat.iconCode,
                  isSelected: selectedCategoryId == cat.id,
                  onTap: () => onCategorySelected(cat.id),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: GestureDetector(
              onTap: onShowAll,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surfaceContainer),
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.onSurfaceVariant,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'الكل',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCircle extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? iconUrl;
  final int? iconCode;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryCircle({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.iconUrl,
    this.iconCode,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.surfaceContainerLow,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.surfaceContainer,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ClipOval(child: _buildIcon()),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (iconUrl != null) {
      return AppNetworkImage(
        iconUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackIcon(),
      );
    }
    if (iconCode != null) {
      return Icon(
        IconData(iconCode!, fontFamily: 'MaterialIcons'),
        color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
        size: 26,
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Icon(
      icon ?? Icons.category_outlined,
      color: iconColor ??
          (isSelected ? AppColors.primary : AppColors.onSurfaceVariant),
      size: 26,
    );
  }
}
