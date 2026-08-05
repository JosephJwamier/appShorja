import 'dart:async';
import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/listing.dart';
import '../models/store.dart';
import '../providers/auth_provider.dart';
import '../services/item_service.dart';
import '../services/store_service.dart';
import '../theme/app_colors.dart';
import '../widgets/home/home_product_card.dart';
import 'store_profile_screen.dart';

class SearchScreen extends StatefulWidget {
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _itemService = ItemService();
  final _storeService = StoreService();
  late final TabController _tabController;
  Timer? _debounce;

  List<FixedListing> _productResults = [];
  List<Store> _storeResults = [];
  bool _isLoading = false;
  String? _error;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _controller.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      _search(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _productResults = [];
        _storeResults = [];
        _hasSearched = false;
      });
      return;
    }

    final token = context.read<AuthProvider>().accessToken ?? '';

    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });

    try {
      if (_tabController.index == 0) {
        final result = await _itemService.fetchFixedListingsPaginated(
          accessToken: token,
          search: query.trim(),
        );
        if (mounted) {
          setState(() {
            _productResults = result.listings;
            _isLoading = false;
          });
        }
      } else {
        final stores = await _storeService.fetchStores(
          accessToken: token,
          search: query.trim(),
        );
        if (mounted) {
          setState(() {
            _storeResults = stores;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Padding(
          padding: const EdgeInsets.only(left: 4, right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: _tabController.index == 0
                  ? 'ابحث عن منتج...'
                  : 'ابحث عن متجر...',
              hintStyle: const TextStyle(
                  color: AppColors.onSurfaceVariant, fontSize: 14),
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          size: 18, color: AppColors.onSurfaceVariant),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _productResults = [];
                          _storeResults = [];
                          _hasSearched = false;
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurfaceVariant,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          onTap: (_) {
            if (_controller.text.trim().isNotEmpty) {
              _search(_controller.text);
            }
          },
          tabs: const [
            Tab(text: 'المنتجات'),
            Tab(text: 'المتاجر'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductResults(),
          _buildStoreResults(),
        ],
      ),
    );
  }

  Widget _buildProductResults() {
    if (_isLoading && _tabController.index == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tabController.index == 0) {
      return _buildError();
    }
    if (!_hasSearched) return _buildIdle('ابحث عن أي منتج...');
    if (_productResults.isEmpty) {
      return _buildEmpty('لا نتائج لـ "${_controller.text}"');
    }
    final cardWidth = (MediaQuery.sizeOf(context).width - 16 * 2 - 12) / 2;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: cardWidth + 150,
      ),
      itemCount: _productResults.length,
      itemBuilder: (context, index) =>
          HomeProductCard(listing: _productResults[index]),
    );
  }

  Widget _buildStoreResults() {
    if (_isLoading && _tabController.index == 1) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tabController.index == 1) {
      return _buildError();
    }
    if (!_hasSearched) return _buildIdle('ابحث عن أي متجر...');
    if (_storeResults.isEmpty) {
      return _buildEmpty('لا متاجر لـ "${_controller.text}"');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _storeResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _StoreCard(store: _storeResults[index]),
    );
  }

  Widget _buildIdle(String hint) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search,
              size: 64, color: AppColors.surfaceContainerHigh),
          const SizedBox(height: 12),
          Text(hint,
              style: const TextStyle(
                  color: AppColors.onSurfaceVariant, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildEmpty(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded,
              size: 64, color: AppColors.surfaceContainerHigh),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 48, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _search(_controller.text),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

// بطاقة متجر في نتائج البحث
class _StoreCard extends StatelessWidget {
  final Store store;
  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoreProfileScreen(store: store),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // شعار المتجر
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceContainer,
                border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: ClipOval(
                child: store.fullLogoUrl != null
                    ? AppNetworkImage(store.fullLogoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.storefront,
                            color: AppColors.onSurfaceVariant))
                    : const Icon(Icons.storefront,
                        color: AppColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 14),
            // معلومات المتجر
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    store.name,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (store.description.isNotEmpty)
                    Text(
                      store.description,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (store.isActive
                                  ? AppColors.primary
                                  : AppColors.onSurfaceVariant)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          store.isActive ? 'نشط' : 'متوقّف',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: store.isActive
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${store.totalItems} منتج',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_left,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
