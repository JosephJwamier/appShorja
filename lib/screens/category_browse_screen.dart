import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/auth_provider.dart';
import '../services/category_service.dart';
import '../theme/app_colors.dart';
import 'category_auctions_screen.dart';
import 'category_products_screen.dart';

/// شاشة تصفّح التصنيفات: قائمة جانبيّة بالتصنيفات الرئيسية على اليمين،
/// ومحتوى التصنيف الفرعي (شبكة) على اليسار — تُفتح عند الضغط على تصنيف في
/// الصفحة الرئيسية أو صفحة المزادات.
class CategoryBrowseScreen extends StatefulWidget {
  final int? initialCategoryId;

  /// عند true: الضغط على تصنيف فرعي يفتح مزادات ذلك التصنيف بدل منتجاته.
  final bool auctionsMode;

  const CategoryBrowseScreen({
    super.key,
    this.initialCategoryId,
    this.auctionsMode = false,
  });

  @override
  State<CategoryBrowseScreen> createState() => _CategoryBrowseScreenState();
}

class _CategoryBrowseScreenState extends State<CategoryBrowseScreen> {
  final _categoryService = CategoryService();

  List<Category> _roots = [];
  bool _loadingRoots = true;
  String? _rootsError;

  Category? _selected;
  List<Category> _subCategories = [];
  bool _loadingSubs = false;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  String get _token => context.read<AuthProvider>().accessToken ?? '';

  Future<void> _loadRoots() async {
    setState(() {
      _loadingRoots = true;
      _rootsError = null;
    });
    try {
      final roots =
          await _categoryService.fetchRootCategories(accessToken: _token);
      if (!mounted) return;
      setState(() {
        _roots = roots;
        _loadingRoots = false;
      });
      if (roots.isNotEmpty) {
        final initial = widget.initialCategoryId != null
            ? roots.where((c) => c.id == widget.initialCategoryId).toList()
            : <Category>[];
        _selectCategory(initial.isNotEmpty ? initial.first : roots.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rootsError = e.toString().replaceFirst('Exception: ', '');
        _loadingRoots = false;
      });
    }
  }

  Future<void> _selectCategory(Category category) async {
    setState(() {
      _selected = category;
      _subCategories = [];
      _loadingSubs = true;
    });
    try {
      final subs = await _categoryService.fetchSubCategories(
        accessToken: _token,
        parentId: category.id,
      );
      if (!mounted) return;
      setState(() {
        _subCategories = subs;
        _loadingSubs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSubs = false);
    }
  }

  void _openProducts(Category category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.auctionsMode
            ? CategoryAuctionsScreen(
                categoryId: category.id,
                title: category.displayName,
              )
            : CategoryProductsScreen(
                categoryId: category.id,
                title: category.displayName,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surfaceContainerLowest,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'التصنيفات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loadingRoots
            ? const Center(child: CircularProgressIndicator())
            : _rootsError != null
                ? _ErrorState(message: _rootsError!, onRetry: _loadRoots)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Sidebar(
                        categories: _roots,
                        selectedId: _selected?.id,
                        onSelect: _selectCategory,
                      ),
                      Expanded(child: _buildContent()),
                    ],
                  ),
      ),
    );
  }

  Widget _buildContent() {
    final selected = _selected;
    if (selected == null) return const SizedBox.shrink();

    return Container(
      color: AppColors.surfaceContainerLowest,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    selected.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loadingSubs)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_subCategories.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'لا توجد تصنيفات فرعية لهذا التصنيف',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 130,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _SubCategoryTile(
                    category: _subCategories[i],
                    onTap: () => _openProducts(_subCategories[i]),
                  ),
                  childCount: _subCategories.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── القائمة الجانبية (التصنيفات الرئيسية) ─────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<Category> onSelect;

  const _Sidebar({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      color: AppColors.surfaceContainerLow,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final cat = categories[i];
          final isSelected = cat.id == selectedId;
          return _SidebarItem(
            category: cat,
            isSelected: isSelected,
            onTap: () => onSelect(cat),
          );
        },
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final Category category;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
            color: isSelected
                ? AppColors.surfaceContainerLowest
                : Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CategoryIcon(category: category, isSelected: isSelected),
                const SizedBox(height: 8),
                Text(
                  category.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: Container(width: 4, color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final Category category;
  final bool isSelected;
  const _CategoryIcon({required this.category, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final color =
        isSelected ? AppColors.primary : AppColors.onSurfaceVariant;
    if (category.iconUrl != null) {
      return ClipOval(
        child: AppNetworkImage(
          category.iconUrl!,
          width: 28,
          height: 28,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              Icon(Icons.category_outlined, color: color, size: 26),
        ),
      );
    }
    if (category.iconCode != null) {
      return Icon(
        IconData(category.iconCode!, fontFamily: 'MaterialIcons'),
        color: color,
        size: 26,
      );
    }
    return Icon(Icons.category_outlined, color: color, size: 26);
  }
}

// ─── بطاقة تصنيف فرعي ───────────────────────────────────────────────────────

class _SubCategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;
  const _SubCategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(14),
              child: category.iconUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AppNetworkImage(
                        category.iconUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.category_outlined,
                          color: AppColors.onSurfaceVariant,
                          size: 32,
                        ),
                      ),
                    )
                  : Icon(
                      category.iconCode != null
                          ? IconData(category.iconCode!,
                              fontFamily: 'MaterialIcons')
                          : Icons.category_outlined,
                      color: AppColors.onSurfaceVariant,
                      size: 32,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            category.displayName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
