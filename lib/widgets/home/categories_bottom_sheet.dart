import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/category.dart';
import '../../theme/app_colors.dart';
import '../../utils/category_icons.dart';

class CategoriesBottomSheet extends StatelessWidget {
  final List<Category> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onSelect;

  const CategoriesBottomSheet({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Category> categories,
    required int? selectedCategoryId,
    required ValueChanged<int?> onSelect,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => CategoriesBottomSheet(
        categories: categories,
        selectedCategoryId: selectedCategoryId,
        onSelect: onSelect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'الفئات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.onSurface),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _CategoryTile(
                  icon: Icons.favorite,
                  iconColor: AppColors.primary,
                  label: 'الكل',
                  isSelected: selectedCategoryId == null,
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(null);
                  },
                ),
                ...categories.map(
                  (cat) => _CategoryTile(
                    iconCode: cat.iconCode,
                    iconUrl: cat.iconUrl,
                    label: cat.displayName,
                    isSelected: selectedCategoryId == cat.id,
                    onTap: () {
                      Navigator.pop(context);
                      onSelect(cat.id);
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? iconColor;
  final String? iconUrl;
  final int? iconCode;

  const _CategoryTile({
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
    return ListTile(
      leading: _buildLeading(),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? AppColors.primary : AppColors.onSurface,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
  }

  Widget _buildLeading() {
    if (iconUrl != null) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: CachedNetworkImageProvider(iconUrl!),
        backgroundColor: AppColors.surfaceContainerLow,
      );
    }
    final data =
        categoryIconFor(iconCode) ?? icon ?? Icons.category_outlined;
    return CircleAvatar(
      radius: 18,
      backgroundColor: isSelected
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surfaceContainerLow,
      child: Icon(data,
          size: 20,
          color: iconColor ??
              (isSelected ? AppColors.primary : AppColors.onSurfaceVariant)),
    );
  }
}
