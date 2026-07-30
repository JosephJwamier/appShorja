import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/deep_link_config.dart';
import '../models/auction.dart';
import '../models/product.dart';
import '../models/store.dart';
import '../models/store_coupon.dart';
import '../providers/auth_provider.dart';
import '../services/auction_service.dart';
import '../services/item_service.dart';
import '../services/store_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/share_helper.dart';
import '../widgets/live/live_store_avatar.dart';
import 'auction_details_screen.dart';
import 'product_details_screen.dart';
import 'store_chat_screen.dart';
import 'store_reviews_screen.dart';

// ملاحظة: أُعيد بناء هذه الشاشة لتطابق تصميم e-Shorja (رأس بصورة غلاف + بطاقة
// إحصاءات + كوبونات + شبكة منتجات). لم يُضَف تبويب «توفير الصيف» ولا قسم
// «التسوق حسب الفئة» بناءً على طلبك.

enum _SortMode { hot, newest, topRated }

class StoreProfileScreen extends StatefulWidget {
  final Store store;
  const StoreProfileScreen({super.key, required this.store});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  final _itemService = ItemService();
  final _storeService = StoreService();
  final _searchController = TextEditingController();

  List<Product> _items = [];
  bool _loadingItems = true;
  String? _itemsError;
  String _query = '';

  // معرّفات المنتجات التي لديها مزاد (نشط أو منتهٍ) — تُستبعد من تبويبات
  // المنتجات ذات السعر الثابت لأن سعرها المعروض قد يكون مأخوذاً من
  // المزاد كقيمة احتياطية وليس من عرض سعر ثابت فعلي.
  Set<int> _auctionItemIds = {};

  late bool _isFollowing;
  late int _followersCount;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.store.isFollowing;
    _followersCount = widget.store.followersCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadItems();
      _loadAuctionItemIds();
    });
  }

  Future<void> _loadAuctionItemIds() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    try {
      final auctions = await AuctionService().fetchAuctionsByStoreUsername(
        accessToken: token,
        username: widget.store.user.username,
      );
      if (mounted) {
        setState(() {
          _auctionItemIds = auctions.map((a) => a.item.id).toSet();
        });
      }
    } catch (_) {
      // تجاهل الخطأ هنا: تبويب المزادات يعرض رسالة الخطأ الخاصة به بالفعل
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    setState(() {
      _loadingItems = true;
      _itemsError = null;
    });
    try {
      final items = await _itemService.fetchItemsByStoreUsername(
        accessToken: token,
        username: widget.store.user.username,
      );
      if (mounted) {
        setState(() {
          _items = items;
          _loadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _itemsError = e.toString().replaceFirst('Exception: ', '');
          _loadingItems = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    setState(() => _followBusy = true);
    final wasFollowing = _isFollowing;
    final r = wasFollowing
        ? await _storeService.unfollowStore(
            accessToken: token, storeId: widget.store.id)
        : await _storeService.followStore(
            accessToken: token, storeId: widget.store.id);
    if (!mounted) return;
    setState(() {
      _followBusy = false;
      if (r.success) {
        _isFollowing = r.isFollowing;
        _followersCount = r.followersCount;
      }
    });
    if (!r.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                r.message.isEmpty ? 'تعذّر تنفيذ العملية' : r.message)),
      );
    }
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoreChatScreen(store: widget.store)),
    );
  }

  bool get _isOwnStore {
    final uid = context.read<AuthProvider>().user?.id;
    return uid != null && uid == widget.store.user.id;
  }

  List<Product> get _filteredItems {
    final q = _query.trim();
    final fixedPriceOnly = _items.where(
      (p) => p.price != null && !_auctionItemIds.contains(p.id),
    );
    if (q.isEmpty) return fixedPriceOnly.toList();
    return fixedPriceOnly.where((p) => p.title.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: DefaultTabController(
          length: 5,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: _CoverHeader(
                  store: widget.store,
                  isFollowing: _isFollowing,
                  followBusy: _followBusy,
                  showActions: !_isOwnStore,
                  searchController: _searchController,
                  onSearchChanged: (v) => setState(() => _query = v),
                  onToggleFollow: _toggleFollow,
                  onContact: _openChat,
                ),
              ),
              SliverToBoxAdapter(
                child: _StatsCard(
                  store: widget.store,
                  followersCount: _followersCount,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoreReviewsScreen(store: widget.store),
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  const TabBar(
                    isScrollable: true,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.onSurfaceVariant,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 3,
                    labelStyle:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    unselectedLabelStyle: TextStyle(fontSize: 15),
                    tabs: [
                      Tab(text: 'الرئيسية'),
                      Tab(text: 'كل المنتجات'),
                      Tab(text: 'وصل حديثاً'),
                      Tab(text: 'المزادات'),
                      Tab(text: 'عن المتجر'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _HomeTab(
                  store: widget.store,
                  items: items,
                  loading: _loadingItems,
                  error: _itemsError,
                  onRetry: _loadItems,
                ),
                _ProductsTab(
                  items: items,
                  loading: _loadingItems,
                  error: _itemsError,
                  onRetry: _loadItems,
                  sort: _SortMode.hot,
                ),
                _ProductsTab(
                  items: items,
                  loading: _loadingItems,
                  error: _itemsError,
                  onRetry: _loadItems,
                  sort: _SortMode.newest,
                ),
                _StoreAuctionsTab(ownerUsername: widget.store.user.username),
                _StoreAboutTab(store: widget.store),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// رأس الغلاف (صورة + عناصر فوقها)
// ══════════════════════════════════════════════════════════════
class _CoverHeader extends StatelessWidget {
  final Store store;
  final bool isFollowing;
  final bool followBusy;
  final bool showActions;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleFollow;
  final VoidCallback onContact;

  const _CoverHeader({
    required this.store,
    required this.isFollowing,
    required this.followBusy,
    required this.showActions,
    required this.searchController,
    required this.onSearchChanged,
    required this.onToggleFollow,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final logo = store.fullLogoUrl;
    final cover = store.fullCoverUrl;
    return SizedBox(
      height: 262,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // خلفية الغلاف: صورة الغلاف إن وُجدت، وإلّا تدرّج أنيق
          if (cover != null)
            Image.network(cover, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _gradientBg())
          else
            _gradientBg(),
          // تدرّج داكن للأسفل
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, Colors.transparent, Colors.black87],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
          // شريط التحكم العلوي: رجوع + بحث + مشاركة (ملاصق لأعلى الشاشة)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                _glassCircle(
                    Icons.arrow_back_ios, () => Navigator.maybePop(context)),
                const SizedBox(width: 10),
                Expanded(child: _searchField()),
                const SizedBox(width: 10),
                _glassCircle(
                  Icons.share_outlined,
                  () => shareLink(
                    context,
                    text: DeepLinkConfig.storeLink(store.id),
                    subject: store.name,
                  ),
                ),
              ],
            ),
          ),
          // معلومات المتجر أسفل الغلاف
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LiveStoreAvatar(store: store, size: 64, avatar: _logoCircle(logo)),
                  const SizedBox(width: 12),
                  Expanded(child: _nameAndBadge()),
                  if (showActions) ...[
                    const SizedBox(width: 8),
                    _contactButton(),
                    const SizedBox(width: 8),
                    _followButton(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientBg() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppColors.secondary, AppColors.onSurface],
          ),
        ),
      );

  Widget _searchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: searchController,
        onChanged: onSearchChanged,
        textDirection: TextDirection.rtl,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'ابحث في المتجر...',
          hintStyle: const TextStyle(color: Colors.white70, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white, size: 20),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.20),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _glassCircle(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _logoCircle(String? logo) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 2),
        image: logo != null
            ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover)
            : null,
      ),
      child: logo == null
          ? const Icon(Icons.storefront, color: AppColors.onSurfaceVariant)
          : null,
    );
  }

  Widget _nameAndBadge() {
    final tier = _tierLabel(store.totalSold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          store.name,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tier,
                style: const TextStyle(
                    color: AppColors.onTertiaryContainer,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            if (store.totalSold > 0)
              Flexible(
                child: Text(
                  'تم بيع +${formatNum(store.totalSold.toDouble())} في 180 يوم',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _contactButton() {
    return GestureDetector(
      onTap: onContact,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: const Icon(Icons.contact_support_outlined,
            color: Colors.white, size: 20),
      ),
    );
  }

  Widget _followButton() {
    final following = isFollowing;
    return GestureDetector(
      onTap: followBusy ? null : onToggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: following
              ? Colors.white.withValues(alpha: 0.20)
              : AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          border: following
              ? Border.all(color: Colors.white.withValues(alpha: 0.5))
              : null,
          boxShadow: following
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (followBusy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(following ? Icons.check : Icons.add,
                  color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              following ? 'متابَع' : 'متابعة',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// بطاقة الإحصاءات
// ══════════════════════════════════════════════════════════════
class _StatsCard extends StatelessWidget {
  final Store store;
  final int followersCount;
  final VoidCallback? onTap;
  const _StatsCard({
    required this.store,
    required this.followersCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _stat(
                  value: store.rating.toStringAsFixed(1),
                  label: 'تقييم المتجر',
                  top: store.rating >= 4.5,
                  highlight: true,
                ),
              ),
              _divider(),
              Expanded(
                child: _stat(
                  value: store.communicationRating.toStringAsFixed(1),
                  label: 'التواصل',
                ),
              ),
              _divider(),
              Expanded(
                child: _stat(
                  value: '${store.positiveReviewPercent.toStringAsFixed(1)}%',
                  label: 'تقييمات إيجابية',
                  top: store.positiveReviewPercent >= 90,
                  highlight: true,
                ),
              ),
              const Icon(Icons.chevron_left,
                  color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
      width: 1, height: 32, color: AppColors.outlineVariant.withValues(alpha: 0.4));

  Widget _stat({
    required String value,
    required String label,
    bool top = false,
    bool highlight = false,
  }) {
    final color = highlight ? AppColors.primary : AppColors.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            if (top) ...[
              const SizedBox(width: 3),
              Text('Top',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.onSurfaceVariant)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// تبويب «الرئيسية»: كوبونات + فلاتر + شبكة منتجات
// ══════════════════════════════════════════════════════════════
class _HomeTab extends StatefulWidget {
  final Store store;
  final List<Product> items;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  const _HomeTab({
    required this.store,
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab>
    with AutomaticKeepAliveClientMixin {
  _SortMode _sort = _SortMode.hot;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sorted = _sortItems(widget.items, _sort);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _CouponsRow(store: widget.store)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('قائمة المتجر',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface)),
                const SizedBox(height: 12),
                _FilterChips(
                  current: _sort,
                  onChanged: (m) => setState(() => _sort = m),
                ),
              ],
            ),
          ),
        ),
        ..._productSlivers(sorted, widget.loading, widget.error, widget.onRetry),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// تبويب المنتجات (كل المنتجات / وصل حديثاً)
// ══════════════════════════════════════════════════════════════
class _ProductsTab extends StatefulWidget {
  final List<Product> items;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final _SortMode sort;
  const _ProductsTab({
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.sort,
  });

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sorted = _sortItems(widget.items, widget.sort);
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ..._productSlivers(sorted, widget.loading, widget.error, widget.onRetry),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// كوبونات المتجر (مطابقة للتصميم)
// ══════════════════════════════════════════════════════════════
class _CouponsRow extends StatefulWidget {
  final Store store;
  const _CouponsRow({required this.store});

  @override
  State<_CouponsRow> createState() => _CouponsRowState();
}

class _CouponsRowState extends State<_CouponsRow> {
  final _service = StoreService();
  List<StoreCoupon> _coupons = [];
  bool _loading = true;
  final Set<int> _collectedIds = {};
  final Set<int> _collecting = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    try {
      final coupons = await _service.fetchStoreCoupons(
          accessToken: token, storeId: widget.store.id);
      if (mounted) {
        setState(() {
          _coupons = coupons;
          for (final c in coupons) {
            if (c.isCollected) _collectedIds.add(c.id);
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _collect(StoreCoupon c) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    setState(() => _collecting.add(c.id));
    final result = await _service.collectCoupon(
        accessToken: token, storeId: widget.store.id, couponId: c.id);
    if (!mounted) return;
    setState(() {
      _collecting.remove(c.id);
      if (result.success) _collectedIds.add(c.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(result.message.isEmpty
              ? (result.success ? 'تم جمع الكوبون' : 'تعذّر الجمع')
              : result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _coupons.isEmpty) return const SizedBox(height: 8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text('الخصومات والكوبونات',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface)),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _coupons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _couponCard(_coupons[i]),
          ),
        ),
      ],
    );
  }

  Widget _couponCard(StoreCoupon c) {
    final collected = _collectedIds.contains(c.id);
    final busy = _collecting.contains(c.id);
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatIqd(c.amount),
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            c.minOrderAmount > 0
                ? 'للطلبات فوق ${formatIqd(c.minOrderAmount)}'
                : 'بدون حد أدنى',
            style: const TextStyle(
                fontSize: 10, color: AppColors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'كود: ${c.code}',
            style: const TextStyle(
                fontSize: 10, color: AppColors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: ElevatedButton(
              onPressed: (collected || busy) ? null : () => _collect(c),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.onSurfaceVariant.withValues(alpha: 0.15),
                padding: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(collected ? 'تم الجمع ✓' : 'جمع الكوبون',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// شرائح الفلترة (قائمة المتجر)
// ══════════════════════════════════════════════════════════════
class _FilterChips extends StatelessWidget {
  final _SortMode current;
  final ValueChanged<_SortMode> onChanged;
  const _FilterChips({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('عروض ساخنة', Icons.local_fire_department, _SortMode.hot),
          const SizedBox(width: 8),
          _chip('الأكثر إضافة', Icons.thumb_up_alt_outlined, _SortMode.newest),
          const SizedBox(width: 8),
          _chip('أفضل التقييمات', Icons.star_outline, _SortMode.topRated),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, _SortMode mode) {
    final active = current == mode;
    return GestureDetector(
      onTap: () => onChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.onSurface : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: active ? Colors.white : AppColors.onSurface),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? Colors.white : AppColors.onSurface)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// بطاقة منتج (مطابقة للتصميم)
// ══════════════════════════════════════════════════════════════
class _DesignProductCard extends StatelessWidget {
  final Product product;
  final int rank;
  const _DesignProductCard({required this.product, required this.rank});

  Future<void> _openDetails(BuildContext context) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final listing = await ItemService().fetchListingByItemId(
        accessToken: token,
        itemId: product.id,
      );
      navigator.pop();
      if (listing != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(
              listing: listing,
              representativeAssignmentId: product.representativeAssignmentId,
            ),
          ),
        );
      } else {
        messenger.showSnackBar(const SnackBar(
            content: Text('لا يوجد عرض سعر ثابت لهذا المنتج بعد')));
      }
    } catch (_) {
      navigator.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('تعذّر فتح تفاصيل المنتج')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = product.firstImage;
    return GestureDetector(
      onTap: () => _openDetails(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (img != null)
                    Image.network(img, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imgFallback())
                  else
                    _imgFallback(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('$rank',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 38,
                    child: Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: AppColors.onSurface),
                    ),
                  ),
                  if ((product.soldCount ?? 0) > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department,
                            size: 13, color: AppColors.primary),
                        const SizedBox(width: 2),
                        Text('${product.soldCount} تم بيعها',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (product.price != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        const Text('IQD ',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                        Text(_priceStr(product.price!),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgFallback() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.inventory_2_outlined,
            color: AppColors.onSurfaceVariant),
      );
}

// ══════════════════════════════════════════════════════════════
// تبويب المزادات
// ══════════════════════════════════════════════════════════════
class _StoreAuctionsTab extends StatefulWidget {
  final String ownerUsername;
  const _StoreAuctionsTab({required this.ownerUsername});

  @override
  State<_StoreAuctionsTab> createState() => _StoreAuctionsTabState();
}

class _StoreAuctionsTabState extends State<_StoreAuctionsTab>
    with AutomaticKeepAliveClientMixin {
  final _service = AuctionService();
  List<Auction> _auctions = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auctions = await _service.fetchAuctionsByStoreUsername(
          accessToken: token, username: widget.ownerUsername);
      if (mounted) {
        setState(() {
          _auctions = auctions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_auctions.isEmpty) {
      return const _EmptyState(
          icon: Icons.gavel_outlined,
          message: 'لا توجد مزادات في هذا المتجر');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _auctions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _AuctionRow(auction: _auctions[i]),
    );
  }
}

class _AuctionRow extends StatelessWidget {
  final Auction auction;
  const _AuctionRow({required this.auction});

  @override
  Widget build(BuildContext context) {
    final img = auction.item.firstImage;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AuctionDetailsScreen(auction: auction)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceContainer),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: img != null
                  ? Image.network(img, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _ph())
                  : _ph(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(auction.item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('السعر الحالي: ',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant)),
                        Text(formatIqd(auction.currentPrice),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.tertiary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _statusChip(auction),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(Auction a) {
    final active = a.isActive;
    final label = active ? 'مزاد نشط' : (a.isUpcoming ? 'قادم' : 'منتهٍ');
    final color = active
        ? AppColors.success
        : (a.isUpcoming ? AppColors.secondary : AppColors.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _ph() => Container(
      color: AppColors.surfaceContainer,
      child: const Icon(Icons.gavel, color: AppColors.onSurfaceVariant));
}

// ══════════════════════════════════════════════════════════════
// تبويب «عن المتجر»
// ══════════════════════════════════════════════════════════════
class _StoreAboutTab extends StatelessWidget {
  final Store store;
  const _StoreAboutTab({required this.store});

  String _joinDate() {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final d = store.createdAt;
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (store.description.isNotEmpty) ...[
          const Text('نبذة عن المتجر',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text(store.description,
              style: const TextStyle(
                  fontSize: 14, height: 1.6, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 20),
        ],
        _infoRow(Icons.event_outlined, 'تاريخ الانضمام', _joinDate()),
        _infoRow(Icons.inventory_2_outlined, 'إجمالي المنتجات',
            '${store.totalItems}'),
        _infoRow(Icons.check_circle_outline, 'المنتجات النشطة',
            '${store.totalActiveItems}'),
        _infoRow(Icons.local_mall_outlined, 'إجمالي المبيعات',
            '${store.totalSold}'),
        _infoRow(Icons.people_outline, 'المتابعون', '${store.followersCount}'),
        if (store.defaultLocation != null &&
            store.defaultLocation!.isNotEmpty)
          _infoRow(Icons.location_on_outlined, 'الموقع', store.defaultLocation!),
        if (store.phoneNumber.isNotEmpty)
          _infoRow(Icons.phone_outlined, 'رقم الهاتف', store.phoneNumber,
              onTap: () => _launchPhone(store.phoneNumber)),
        if (store.whatsappNumber.isNotEmpty)
          _infoRow(Icons.chat_outlined, 'واتساب', store.whatsappNumber,
              onTap: () => _launchWhatsapp(store.whatsappNumber)),
        _infoRow(
            store.isActive ? Icons.storefront : Icons.pause_circle_outline,
            'الحالة',
            store.isActive ? 'متجر نشط' : 'متوقّف'),
      ],
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsapp(String phone) async {
    final uri = Uri.parse('https://wa.me/${toWhatsappDigits(phone)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _infoRow(IconData icon, String label, String value,
      {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.onSurfaceVariant)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.left,
                textDirection: TextDirection.ltr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onTap != null
                        ? AppColors.primary
                        : AppColors.onSurface)),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 56,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// شريط التبويبات المثبّت
// ══════════════════════════════════════════════════════════════
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════
// أدوات مشتركة
// ══════════════════════════════════════════════════════════════
List<Product> _sortItems(List<Product> items, _SortMode mode) {
  final list = List<Product>.from(items);
  switch (mode) {
    case _SortMode.hot:
      list.sort((a, b) => (b.soldCount ?? 0).compareTo(a.soldCount ?? 0));
      break;
    case _SortMode.newest:
      list.sort((a, b) => b.id.compareTo(a.id));
      break;
    case _SortMode.topRated:
      list.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      break;
  }
  return list;
}

List<Widget> _productSlivers(
    List<Product> items, bool loading, String? error, VoidCallback onRetry) {
  if (loading) {
    return const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    ];
  }
  if (error != null) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(error, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('إعادة المحاولة')),
              ],
            ),
          ),
        ),
      ),
    ];
  }
  if (items.isEmpty) {
    return const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 48, color: AppColors.onSurfaceVariant),
                SizedBox(height: 12),
                Text('لا توجد منتجات في هذا المتجر بعد',
                    style: TextStyle(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    ];
  }
  return [
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 0.62,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _DesignProductCard(product: items[i], rank: i + 1),
          childCount: items.length,
        ),
      ),
    ),
  ];
}

// ══════════════════════════════════════════════════════════════
// زر «زيارة المتجر»: يجلب المتجر عبر اسم المستخدم وينتقل إلى ملفه
// ══════════════════════════════════════════════════════════════
class VisitStoreButton extends StatelessWidget {
  final String ownerUsername;
  const VisitStoreButton({super.key, required this.ownerUsername});

  Future<void> _visitStore(BuildContext context) async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final store = await StoreService().fetchStoreByUsername(
          accessToken: token, username: ownerUsername);
      navigator.pop();
      if (store != null) {
        navigator.push(
          MaterialPageRoute(builder: (_) => StoreProfileScreen(store: store)),
        );
      } else {
        messenger
            .showSnackBar(const SnackBar(content: Text('تعذّر فتح المتجر')));
      }
    } catch (_) {
      navigator.pop();
      messenger
          .showSnackBar(const SnackBar(content: Text('تعذّر فتح المتجر')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _visitStore(context),
      icon: const Icon(Icons.storefront_outlined, size: 16),
      label: const Text('زيارة المتجر'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

String _priceStr(double v) {
  final whole = formatNum(v);
  if (v == v.truncateToDouble()) return whole;
  final frac =
      ((v - v.truncateToDouble()) * 100).round().toString().padLeft(2, '0');
  return '$whole.$frac';
}

String _tierLabel(int sold) {
  if (sold >= 1000) return 'ذهبي Gold';
  if (sold >= 100) return 'فضي Silver';
  return 'برونزي Bronze';
}
