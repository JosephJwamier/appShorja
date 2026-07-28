import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/filter_params.dart';
import '../services/category_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Opens the sort bottom sheet and returns the chosen ordering value,
/// or null if the user dismissed without choosing.
Future<String?> showSortBottomSheet(
  BuildContext context,
  String currentOrdering,
) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SortBottomSheet(currentOrdering: currentOrdering),
  );
}

class _SortBottomSheet extends StatelessWidget {
  final String currentOrdering;
  const _SortBottomSheet({required this.currentOrdering});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الترتيب',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...FilterParams.sortOptions.map((opt) {
            final isSelected = opt.$1 == currentOrdering;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(
                opt.$2,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.onSurface,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(context, opt.$1),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// FilterScreen
// ─────────────────────────────────────────────

class FilterScreen extends StatefulWidget {
  final FilterParams initialFilters;
  final String accessToken;

  const FilterScreen({
    super.key,
    required this.initialFilters,
    required this.accessToken,
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final _categoryService = CategoryService();
  final _cityController = TextEditingController();

  // Category state
  List<Category> _rootCategories = [];
  List<Category> _subCategories = [];
  bool _loadingRoots = true;
  bool _loadingSubs = false;
  int? _selectedRootId;
  int? _selectedSubId;

  // Filter state
  String? _selectedCondition;
  double _minPrice = FilterParams.minBound;
  double _maxPrice = FilterParams.maxBound;
  double _minDeposit = FilterParams.minDepositBound;
  double _maxDeposit = FilterParams.maxDepositBound;
  bool _isDailyDeal = false;
  bool _hasDiscount = false;
  String _ordering = '-created_at';

  @override
  void initState() {
    super.initState();
    _initFromFilters();
    _loadRootCategories();
  }

  void _initFromFilters() {
    final f = widget.initialFilters;
    _selectedCondition = f.condition;
    _minPrice = f.minPrice;
    _maxPrice = f.maxPrice;
    _minDeposit = f.minDeposit;
    _maxDeposit = f.maxDeposit;
    _cityController.text = f.city ?? '';
    _isDailyDeal = f.isDailyDeal;
    _hasDiscount = f.hasDiscount;
    _ordering = f.ordering;
    // categoryId will be matched after roots are loaded
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadRootCategories() async {
    setState(() => _loadingRoots = true);
    try {
      final roots = await _categoryService.fetchRootCategories(
        accessToken: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _rootCategories = roots;
        _loadingRoots = false;
        // Try to pre-select the category from initialFilters
        final initId = widget.initialFilters.categoryId;
        if (initId != null) {
          final match = roots.where((c) => c.id == initId).toList();
          if (match.isNotEmpty) {
            _selectedRootId = match.first.id;
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRoots = false);
    }
  }

  Future<void> _onRootSelected(Category cat) async {
    if (_selectedRootId == cat.id) {
      // deselect
      setState(() {
        _selectedRootId = null;
        _selectedSubId = null;
        _subCategories = [];
      });
      return;
    }
    setState(() {
      _selectedRootId = cat.id;
      _selectedSubId = null;
      _subCategories = [];
      _loadingSubs = true;
    });
    try {
      final subs = await _categoryService.fetchSubCategories(
        accessToken: widget.accessToken,
        parentId: cat.id,
      );
      if (!mounted) return;
      setState(() {
        _subCategories = subs;
        _loadingSubs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  void _onSubSelected(Category cat) {
    setState(() {
      _selectedSubId = _selectedSubId == cat.id ? null : cat.id;
    });
  }

  void _resetAll() {
    setState(() {
      _selectedRootId = null;
      _selectedSubId = null;
      _subCategories = [];
      _selectedCondition = null;
      _minPrice = FilterParams.minBound;
      _maxPrice = FilterParams.maxBound;
      _minDeposit = FilterParams.minDepositBound;
      _maxDeposit = FilterParams.maxDepositBound;
      _cityController.clear();
      _isDailyDeal = false;
      _hasDiscount = false;
      _ordering = '-created_at';
    });
  }

  void _applyFilters() {
    final result = FilterParams(
      categoryId: _selectedSubId ?? _selectedRootId,
      condition: _selectedCondition,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      minDeposit: _minDeposit,
      maxDeposit: _maxDeposit,
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      isDailyDeal: _isDailyDeal,
      hasDiscount: _hasDiscount,
      ordering: _ordering,
    );
    Navigator.pop(context, result);
  }

  Future<void> _openSortSheet() async {
    final chosen = await showSortBottomSheet(context, _ordering);
    if (chosen != null && mounted) {
      setState(() => _ordering = chosen);
    }
  }

  String get _sortLabel {
    return FilterParams.sortOptions
        .firstWhere(
          (o) => o.$1 == _ordering,
          orElse: () => ('-created_at', 'الأحدث'),
        )
        .$2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'التصفية',
          style: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: const Text(
              'إعادة تعيين',
              style: TextStyle(color: AppColors.primary, fontSize: 14),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildCategorySection(),
                  _divider(),
                  _buildConditionSection(),
                  _divider(),
                  _buildPriceSection(),
                  _divider(),
                  _buildDepositSection(),
                  _divider(),
                  _buildCitySection(),
                  _divider(),
                  _buildTogglesSection(),
                  _divider(),
                  _buildSortSection(),
                ],
              ),
            ),
          ),
          _buildApplyButton(),
        ],
      ),
    );
  }

  // ── Sections ──────────────────────────────────

  Widget _buildCategorySection() {
    return _Section(
      title: 'الفئة',
      child: _loadingRoots
          ? const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Root categories
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._rootCategories.map((cat) {
                      final isSelected = _selectedRootId == cat.id;
                      return _FilterChip(
                        label: cat.displayName,
                        selected: isSelected,
                        onTap: () => _onRootSelected(cat),
                      );
                    }),
                  ],
                ),
                // Sub-categories
                if (_loadingSubs)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_subCategories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'الفئة الفرعية',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _subCategories.map((cat) {
                      final isSelected = _selectedSubId == cat.id;
                      return _FilterChip(
                        label: cat.displayName,
                        selected: isSelected,
                        onTap: () => _onSubSelected(cat),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildConditionSection() {
    return _Section(
      title: 'الحالة',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: FilterParams.conditions.map((cond) {
          final isSelected = _selectedCondition == cond.$1;
          return _FilterChip(
            label: cond.$2,
            selected: isSelected,
            onTap: () => setState(() {
              _selectedCondition = isSelected ? null : cond.$1;
            }),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriceSection() {
    return _Section(
      title: 'نطاق السعر',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatIqd(_minPrice),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _maxPrice >= FilterParams.maxBound
                    ? 'بدون حد أقصى'
                    : formatIqd(_maxPrice),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RangeSlider(
            values: RangeValues(_minPrice, _maxPrice),
            min: FilterParams.minBound,
            max: FilterParams.maxBound,
            divisions: 100,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.surfaceContainerHigh,
            onChanged: (values) => setState(() {
              _minPrice = values.start;
              _maxPrice = values.end;
            }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatIqd(FilterParams.minBound),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
              Text(
                '${formatIqd(FilterParams.maxBound)}+',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDepositSection() {
    return _Section(
      title: 'نسبة الوديعة %',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_minDeposit.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _maxDeposit >= FilterParams.maxDepositBound
                    ? 'بدون حد أقصى'
                    : '${_maxDeposit.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RangeSlider(
            values: RangeValues(_minDeposit, _maxDeposit),
            min: FilterParams.minDepositBound,
            max: FilterParams.maxDepositBound,
            divisions: 100,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.surfaceContainerHigh,
            onChanged: (values) => setState(() {
              _minDeposit = values.start;
              _maxDeposit = values.end;
            }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${FilterParams.minDepositBound.toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
              Text(
                '${FilterParams.maxDepositBound.toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCitySection() {
    return _Section(
      title: 'المدينة',
      child: TextField(
        controller: _cityController,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'مثال: بغداد، البصرة...',
          hintStyle: const TextStyle(
              color: AppColors.onSurfaceVariant, fontSize: 14),
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _cityController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      size: 18, color: AppColors.onSurfaceVariant),
                  onPressed: () => setState(() => _cityController.clear()),
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTogglesSection() {
    return _Section(
      title: 'خيارات إضافية',
      child: Column(
        children: [
          _ToggleTile(
            label: 'عروض اليوم فقط',
            icon: Icons.local_fire_department_rounded,
            value: _isDailyDeal,
            onChanged: (v) => setState(() => _isDailyDeal = v),
          ),
          const SizedBox(height: 4),
          _ToggleTile(
            label: 'عليها خصم',
            icon: Icons.discount_rounded,
            value: _hasDiscount,
            onChanged: (v) => setState(() => _hasDiscount = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSection() {
    return _Section(
      title: 'الترتيب',
      child: InkWell(
        onTap: _openSortSheet,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.swap_vert_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sortLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_left_rounded,
                  color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplyButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _applyFilters,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'تطبيق الفلتر',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppColors.surfaceContainerHigh, height: 1),
      );
}

// ─────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.surfaceContainer,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.white : AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 20,
            color: value ? AppColors.primary : AppColors.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: value ? AppColors.onSurface : AppColors.onSurfaceVariant,
              fontWeight: value ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Auction Sort Bottom Sheet
// ─────────────────────────────────────────────

Future<String?> showAuctionSortBottomSheet(
  BuildContext context,
  String currentOrdering,
) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AuctionSortBottomSheet(currentOrdering: currentOrdering),
  );
}

class _AuctionSortBottomSheet extends StatelessWidget {
  final String currentOrdering;
  const _AuctionSortBottomSheet({required this.currentOrdering});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الترتيب',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...FilterParams.auctionSortOptions.map((opt) {
            final isSelected = opt.$1 == currentOrdering;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(
                opt.$2,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.onSurface,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(context, opt.$1),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AuctionFilterScreen
// ─────────────────────────────────────────────

class AuctionFilterScreen extends StatefulWidget {
  final FilterParams initialFilters;
  final String accessToken;

  const AuctionFilterScreen({
    super.key,
    required this.initialFilters,
    required this.accessToken,
  });

  @override
  State<AuctionFilterScreen> createState() => _AuctionFilterScreenState();
}

class _AuctionFilterScreenState extends State<AuctionFilterScreen> {
  final _categoryService = CategoryService();
  final _cityController = TextEditingController();

  List<Category> _rootCategories = [];
  List<Category> _subCategories = [];
  bool _loadingRoots = true;
  bool _loadingSubs = false;
  int? _selectedRootId;
  int? _selectedSubId;

  String? _selectedCondition;
  double _minPrice = FilterParams.minBound;
  double _maxPrice = FilterParams.maxBound;
  String _ordering = '-created_at';

  @override
  void initState() {
    super.initState();
    _initFromFilters();
    _loadRootCategories();
  }

  void _initFromFilters() {
    final f = widget.initialFilters;
    _selectedCondition = f.condition;
    _minPrice = f.minPrice;
    _maxPrice = f.maxPrice;
    _cityController.text = f.city ?? '';
    _ordering = f.ordering;
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadRootCategories() async {
    setState(() => _loadingRoots = true);
    try {
      final roots = await _categoryService.fetchRootCategories(
        accessToken: widget.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _rootCategories = roots;
        _loadingRoots = false;
        final initId = widget.initialFilters.categoryId;
        if (initId != null) {
          final match = roots.where((c) => c.id == initId).toList();
          if (match.isNotEmpty) _selectedRootId = match.first.id;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRoots = false);
    }
  }

  Future<void> _onRootSelected(Category cat) async {
    if (_selectedRootId == cat.id) {
      setState(() {
        _selectedRootId = null;
        _selectedSubId = null;
        _subCategories = [];
      });
      return;
    }
    setState(() {
      _selectedRootId = cat.id;
      _selectedSubId = null;
      _subCategories = [];
      _loadingSubs = true;
    });
    try {
      final subs = await _categoryService.fetchSubCategories(
        accessToken: widget.accessToken,
        parentId: cat.id,
      );
      if (!mounted) return;
      setState(() {
        _subCategories = subs;
        _loadingSubs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSubs = false);
    }
  }

  void _onSubSelected(Category cat) {
    setState(() {
      _selectedSubId = _selectedSubId == cat.id ? null : cat.id;
    });
  }

  void _resetAll() {
    setState(() {
      _selectedRootId = null;
      _selectedSubId = null;
      _subCategories = [];
      _selectedCondition = null;
      _minPrice = FilterParams.minBound;
      _maxPrice = FilterParams.maxBound;
      _cityController.clear();
      _ordering = '-created_at';
    });
  }

  void _applyFilters() {
    final result = FilterParams(
      categoryId: _selectedSubId ?? _selectedRootId,
      condition: _selectedCondition,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      ordering: _ordering,
    );
    Navigator.pop(context, result);
  }

  Future<void> _openSortSheet() async {
    final chosen = await showAuctionSortBottomSheet(context, _ordering);
    if (chosen != null && mounted) setState(() => _ordering = chosen);
  }

  String get _sortLabel {
    return FilterParams.auctionSortOptions
        .firstWhere(
          (o) => o.$1 == _ordering,
          orElse: () => ('-created_at', 'الأحدث'),
        )
        .$2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'تصفية المزادات',
          style: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: const Text(
              'إعادة تعيين',
              style: TextStyle(color: AppColors.primary, fontSize: 14),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _buildCategorySection(),
                  _divider(),
                  _buildConditionSection(),
                  _divider(),
                  _buildPriceSection(),
                  _divider(),
                  _buildCitySection(),
                  _divider(),
                  _buildSortSection(),
                ],
              ),
            ),
          ),
          _buildApplyButton(),
        ],
      ),
    );
  }

  Widget _buildCategorySection() {
    return _Section(
      title: 'الفئة',
      child: _loadingRoots
          ? const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _rootCategories.map((cat) {
                    final isSelected = _selectedRootId == cat.id;
                    return _FilterChip(
                      label: cat.displayName,
                      selected: isSelected,
                      onTap: () => _onRootSelected(cat),
                    );
                  }).toList(),
                ),
                if (_loadingSubs)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_subCategories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'الفئة الفرعية',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _subCategories.map((cat) {
                      final isSelected = _selectedSubId == cat.id;
                      return _FilterChip(
                        label: cat.displayName,
                        selected: isSelected,
                        onTap: () => _onSubSelected(cat),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildConditionSection() {
    return _Section(
      title: 'حالة المنتج',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: FilterParams.conditions.map((cond) {
          final isSelected = _selectedCondition == cond.$1;
          return _FilterChip(
            label: cond.$2,
            selected: isSelected,
            onTap: () => setState(() {
              _selectedCondition = isSelected ? null : cond.$1;
            }),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPriceSection() {
    return _Section(
      title: 'نطاق السعر',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatIqd(_minPrice),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _maxPrice >= FilterParams.maxBound
                    ? 'بدون حد أقصى'
                    : formatIqd(_maxPrice),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RangeSlider(
            values: RangeValues(_minPrice, _maxPrice),
            min: FilterParams.minBound,
            max: FilterParams.maxBound,
            divisions: 100,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.surfaceContainerHigh,
            onChanged: (values) => setState(() {
              _minPrice = values.start;
              _maxPrice = values.end;
            }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatIqd(FilterParams.minBound),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
              Text(
                '${formatIqd(FilterParams.maxBound)}+',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCitySection() {
    return _Section(
      title: 'المدينة',
      child: TextField(
        controller: _cityController,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'مثال: بغداد، البصرة...',
          hintStyle: const TextStyle(
              color: AppColors.onSurfaceVariant, fontSize: 14),
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _cityController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      size: 18, color: AppColors.onSurfaceVariant),
                  onPressed: () => setState(() => _cityController.clear()),
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildSortSection() {
    return _Section(
      title: 'الترتيب',
      child: InkWell(
        onTap: _openSortSheet,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.swap_vert_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sortLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_left_rounded,
                  color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplyButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _applyFilters,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'تطبيق الفلتر',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: AppColors.surfaceContainerHigh, height: 1),
      );
}
