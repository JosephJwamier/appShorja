import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/auction.dart';
import '../models/filter_params.dart';
import '../utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/auctions_provider.dart';
import '../providers/category_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/home/categories_row.dart';
import '../widgets/home/categories_bottom_sheet.dart';
import 'auction_details_screen.dart';
import 'category_browse_screen.dart';
import 'filter_screen.dart';

enum _AuctionFilter { all, active, endingSoon }

// ===== الشاشة المستقلّة (بشريط علويّ كامل) =====
class AuctionsScreen extends StatefulWidget {
  const AuctionsScreen({super.key});

  @override
  State<AuctionsScreen> createState() => _AuctionsScreenState();
}

class _AuctionsScreenState extends State<AuctionsScreen> {
  Timer? _ticker;
  Timer? _debounce;
  _AuctionFilter _filter = _AuctionFilter.all;
  FilterParams _filters = FilterParams.empty;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadCategories();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<AuctionsProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await provider.loadAuctions(
        accessToken: auth.accessToken!,
        filters: _filters,
      );
    }
  }

  Future<void> _loadCategories() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await Provider.of<CategoryProvider>(
        context,
        listen: false,
      ).loadCategories(accessToken: auth.accessToken!);
    }
  }

  Future<void> _loadMore() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<AuctionsProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await provider.loadMore(accessToken: auth.accessToken!);
    }
  }

  Future<void> _openFilters() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.accessToken == null) return;
    final result = await Navigator.push<FilterParams>(
      context,
      MaterialPageRoute(
        builder: (_) => AuctionFilterScreen(
          initialFilters: _filters,
          accessToken: auth.accessToken!,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _filters = result);
      _load();
    }
  }

  void _onCategorySelected(int? categoryId) {
    if (categoryId == null) {
      setState(() {
        _filters = _filters.copyWith(categoryId: null);
      });
      _load();
      return;
    }

    // البنر (الصف وقائمة "عرض الكل") يعرض التصنيفات الرئيسية فقط، فالضغط على
    // أيّ منها يفتح شاشة تصفّح التصنيفات دائماً بدل التصفية في مكانها.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryBrowseScreen(
          initialCategoryId: categoryId,
          auctionsMode: true,
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _debounce?.cancel();
        _load();
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final provider = Provider.of<AuctionsProvider>(context, listen: false);
      if (auth.accessToken != null) {
        provider.loadAuctions(
          accessToken: auth.accessToken!,
          search: value.trim().isNotEmpty ? value.trim() : null,
          filters: _filters,
        );
      }
    });
  }

  List<Auction> _applyFilter(List<Auction> all) {
    switch (_filter) {
      case _AuctionFilter.all:
        return all;
      case _AuctionFilter.active:
        return all.where((a) => a.isActive).toList();
      case _AuctionFilter.endingSoon:
        return all.where((a) {
          if (!a.isActive) return false;
          final remaining = a.endTime.difference(DateTime.now()).inSeconds;
          return remaining > 0 && remaining <= 3600;
        }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              _AuctionsTopBar(
                searching: _searching,
                controller: _searchController,
                onToggleSearch: _toggleSearch,
                onChanged: _onSearchChanged,
                onOpenFilters: _openFilters,
                hasActiveFilters: _filters.hasActiveAuctionFilters,
              ),
              _AuctionsFilterBar(
                filter: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              _AuctionsCategoriesRow(
                selectedCategoryId: _filters.categoryId,
                onCategorySelected: _onCategorySelected,
              ),
              Expanded(
                child: Consumer<AuctionsProvider>(
                  builder: (context, provider, child) {
                    if (provider.isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (provider.errorMessage != null) {
                      return _ErrorView(
                        message: provider.errorMessage!,
                        onRetry: _load,
                      );
                    }
                    if (provider.auctions.isEmpty) {
                      return const Center(child: Text('لا توجد مزادات حالياً'));
                    }
                    final filtered = _applyFilter(provider.auctions);
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          'لا توجد مزادات تطابق بحثك',
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: filtered.length + (provider.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == filtered.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return AuctionCard(auction: filtered[index]);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== نسخة تُستخدم داخل MainShell =====
class AuctionsListView extends StatefulWidget {
  final String searchQuery;
  const AuctionsListView({super.key, this.searchQuery = ''});

  @override
  State<AuctionsListView> createState() => _AuctionsListViewState();
}

class _AuctionsListViewState extends State<AuctionsListView> {
  Timer? _ticker;
  Timer? _debounce;
  _AuctionFilter _filter = _AuctionFilter.all;
  FilterParams _filters = FilterParams.empty;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadCategories();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AuctionsListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery && !_searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadWithSearch(widget.searchQuery);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<AuctionsProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await provider.loadAuctions(
        accessToken: auth.accessToken!,
        filters: _filters,
      );
    }
  }

  Future<void> _loadCategories() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await Provider.of<CategoryProvider>(
        context,
        listen: false,
      ).loadCategories(accessToken: auth.accessToken!);
    }
  }

  Future<void> _loadWithSearch(String search) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<AuctionsProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await provider.loadAuctions(
        accessToken: auth.accessToken!,
        search: search.trim().isNotEmpty ? search.trim() : null,
        filters: _filters,
      );
    }
  }

  Future<void> _loadMore() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<AuctionsProvider>(context, listen: false);
    if (auth.accessToken != null) {
      await provider.loadMore(accessToken: auth.accessToken!);
    }
  }

  Future<void> _openFilters() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.accessToken == null) return;
    final result = await Navigator.push<FilterParams>(
      context,
      MaterialPageRoute(
        builder: (_) => AuctionFilterScreen(
          initialFilters: _filters,
          accessToken: auth.accessToken!,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _filters = result);
      _load();
    }
  }

  void _onCategorySelected(int? categoryId) {
    if (categoryId == null) {
      setState(() {
        _filters = _filters.copyWith(categoryId: null);
      });
      _load();
      return;
    }

    // البنر (الصف وقائمة "عرض الكل") يعرض التصنيفات الرئيسية فقط، فالضغط على
    // أيّ منها يفتح شاشة تصفّح التصنيفات دائماً بدل التصفية في مكانها.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryBrowseScreen(
          initialCategoryId: categoryId,
          auctionsMode: true,
        ),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _debounce?.cancel();
        _loadWithSearch(widget.searchQuery);
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final provider = Provider.of<AuctionsProvider>(context, listen: false);
      if (auth.accessToken != null) {
        provider.loadAuctions(
          accessToken: auth.accessToken!,
          search: value.trim().isNotEmpty ? value.trim() : null,
          filters: _filters,
        );
      }
    });
  }

  List<Auction> _applyFilter(List<Auction> all) {
    switch (_filter) {
      case _AuctionFilter.all:
        return all;
      case _AuctionFilter.active:
        return all.where((a) => a.isActive).toList();
      case _AuctionFilter.endingSoon:
        return all.where((a) {
          if (!a.isActive) return false;
          final remaining = a.endTime.difference(DateTime.now()).inSeconds;
          return remaining > 0 && remaining <= 3600;
        }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _AuctionsTopBar(
              searching: _searching,
              controller: _searchController,
              onToggleSearch: _toggleSearch,
              onChanged: _onSearchChanged,
              onOpenFilters: _openFilters,
              hasActiveFilters: _filters.hasActiveAuctionFilters,
            ),
            _AuctionsFilterBar(
              filter: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            _AuctionsCategoriesRow(
              selectedCategoryId: _filters.categoryId,
              onCategorySelected: _onCategorySelected,
            ),
            Expanded(
              child: Consumer<AuctionsProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading && provider.auctions.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.errorMessage != null &&
                      provider.auctions.isEmpty) {
                    return _ErrorView(
                      message: provider.errorMessage!,
                      onRetry: _load,
                    );
                  }
                  if (provider.auctions.isEmpty) {
                    return const Center(child: Text('لا توجد مزادات بعد'));
                  }
                  final list = _applyFilter(provider.auctions);
                  if (list.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد مزادات تطابق بحثك',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: list.length + (provider.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == list.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return AuctionCard(auction: list[index]);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== الشريط العلويّ المشترك (بوضع بحث) =====
class _AuctionsTopBar extends StatelessWidget {
  final bool searching;
  final TextEditingController controller;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onChanged;
  final VoidCallback onOpenFilters;
  final bool hasActiveFilters;
  const _AuctionsTopBar({
    required this.searching,
    required this.controller,
    required this.onToggleSearch,
    required this.onChanged,
    required this.onOpenFilters,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: searching
            ? Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        textAlign: TextAlign.right,
                        onChanged: onChanged,
                        decoration: InputDecoration(
                          hintText: 'ابحث في المزادات...',
                          filled: true,
                          fillColor: AppColors.surfaceContainer,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.primaryContainer,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.onSurfaceVariant,
                    ),
                    onPressed: onToggleSearch,
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onToggleSearch,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.search,
                              color: AppColors.onSurfaceVariant,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Stack(
                        children: [
                          Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onOpenFilters,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.tune_rounded,
                                  color: hasActiveFilters
                                      ? AppColors.primary
                                      : AppColors.onSurfaceVariant,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                          if (hasActiveFilters)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceContainer,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          color: AppColors.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'المزادات المباشرة',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ===== شريط رقاقات التصفية المشترك =====
class _AuctionsFilterBar extends StatelessWidget {
  final _AuctionFilter filter;
  final ValueChanged<_AuctionFilter> onChanged;
  const _AuctionsFilterBar({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _FilterChip(
              label: 'الكل',
              selected: filter == _AuctionFilter.all,
              onTap: () => onChanged(_AuctionFilter.all),
            ),
            _FilterChip(
              label: 'نشط',
              selected: filter == _AuctionFilter.active,
              onTap: () => onChanged(_AuctionFilter.active),
            ),
            _FilterChip(
              label: 'ينتهي قريباً',
              selected: filter == _AuctionFilter.endingSoon,
              onTap: () => onChanged(_AuctionFilter.endingSoon),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== صف الفئات (نفس نمط الصفحة الرئيسية) =====
class _AuctionsCategoriesRow extends StatelessWidget {
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategorySelected;
  const _AuctionsCategoriesRow({
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CategoryProvider>(
      builder: (ctx, catProv, _) {
        if (catProv.isLoading) {
          return const SizedBox(
            height: 90,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        // الصف يعرض التصنيفات الرئيسية فقط (وليس كل التصنيفات الفرعية
        // المسطّحة) — الضغط على أيّ منها يفتح شاشة تصفّح التصنيفات.
        final rootCategories =
            catProv.categories.where((c) => c.isRoot).toList();
        if (rootCategories.isEmpty) {
          return const SizedBox.shrink();
        }
        return CategoriesRow(
          categories: rootCategories,
          selectedCategoryId: selectedCategoryId,
          onCategorySelected: onCategorySelected,
          onShowAll: () => CategoriesBottomSheet.show(
            ctx,
            categories: rootCategories,
            selectedCategoryId: selectedCategoryId,
            onSelect: onCategorySelected,
          ),
        );
      },
    );
  }
}

// ===== عرض الخطأ المشترك =====
class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 50, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== رقاقة تصفية =====
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
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.onSurfaceVariant,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ===== بطاقة المزاد الكبيرة (عامّة — تُستخدم أيضاً في شاشة مزادات التصنيف) =====
class AuctionCard extends StatelessWidget {
  final Auction auction;
  const AuctionCard({super.key, required this.auction});

  static const _gold = Color(0xFFF7C948);

  String _formatTime(int seconds) {
    if (seconds <= 0) return 'انتهى';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '$days يوم $hours ساعة';
    if (hours > 0) return '$hours ساعة $minutes دقيقة';
    if (minutes > 0) return '$minutes دقيقة';
    return '$seconds ثانية';
  }

  String _clock() {
    final now = DateTime.now();
    int total;
    if (auction.isUpcoming) {
      total = auction.startTime.difference(now).inSeconds;
    } else if (auction.isActive) {
      total = auction.endTime.difference(now).inSeconds;
    } else {
      return 'انتهى';
    }
    if (total <= 0) return auction.isUpcoming ? 'يبدأ الآن' : 'انتهى';
    if (total >= 86400) return _formatTime(total);
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final item = auction.item;

    final Color badgeColor;
    final String badgeLabel;
    if (auction.isActive) {
      badgeColor = _gold;
      badgeLabel = 'مباشر';
    } else if (auction.isUpcoming) {
      badgeColor = AppColors.secondary;
      badgeLabel = 'قادم';
    } else {
      badgeColor = AppColors.onSurfaceVariant;
      badgeLabel = 'منتهي';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 240,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.firstImage != null
                      ? Image.network(
                          item.firstImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.surfaceContainer,
                            child: const Icon(Icons.broken_image, size: 48),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceContainer,
                          child: const Icon(Icons.image, size: 48),
                        ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.onSurface,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            badgeLabel,
                            style: const TextStyle(
                              color: AppColors.onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC000000), Color(0x00000000)],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.groups,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${auction.bidCount} مزايد',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'الوقت المتبقّي',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _clock(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'أعلى مزايدة',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          textBaseline: TextBaseline.alphabetic,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          children: [
                            Text(
                              formatNum(auction.currentPrice),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'IQD',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.description,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AuctionDetailsScreen(auction: auction),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: auction.isActive
                          ? AppColors.primary
                          : AppColors.surfaceContainerHigh,
                      foregroundColor: auction.isActive
                          ? Colors.white
                          : AppColors.onSurface,
                      elevation: auction.isActive ? 4 : 0,
                      shadowColor: AppColors.primary.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          auction.isActive ? 'زايد الآن' : 'عرض التفاصيل',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (auction.isActive) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.gavel, size: 20),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
