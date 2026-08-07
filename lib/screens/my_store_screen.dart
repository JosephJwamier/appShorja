import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../config/deep_link_config.dart';
import '../models/auction.dart';
import '../models/representative_request.dart';
import '../models/store.dart';
import '../providers/auth_provider.dart';
import '../providers/store_provider.dart';
import '../providers/my_items_provider.dart';
import '../providers/representative_requests_provider.dart';
import '../services/auction_service.dart';
import '../services/item_service.dart';
import '../utils/formatters.dart';
import '../utils/share_helper.dart';
import '../theme/app_colors.dart';
import 'auction_details_screen.dart';
import 'create_store_screen.dart';
import 'edit_auction_screen.dart';
import 'edit_store_screen.dart';
import 'manage_coupons_screen.dart';
import 'product_details_screen.dart';

class MyStoreScreen extends StatefulWidget {
  const MyStoreScreen({super.key});

  @override
  State<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends State<MyStoreScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<StoreProvider>(context, listen: false);
    await provider.loadMyStore(accessToken: auth.accessToken!);

    if (auth.user != null) {
      await Provider.of<MyItemsProvider>(context, listen: false).loadMyItems(
        accessToken: auth.accessToken!,
        ownerId: auth.user!.id,
      );
      await Provider.of<RepresentativeRequestsProvider>(context, listen: false)
          .loadActiveRepresentatives(accessToken: auth.accessToken!);
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Consumer<StoreProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.myStore == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.errorMessage != null && provider.myStore == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 50, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(provider.errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (provider.myStore == null) {
            return SafeArea(child: _CreateStorePrompt(onRefresh: _load));
          }
          return _StoreView(
            store: provider.myStore!,
            dateFormatter: _formatDate,
            onRefresh: _load,
          );
        },
      ),
    );
  }
}

class _CreateStorePrompt extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _CreateStorePrompt({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined,
                size: 100, color: AppColors.outline),
            const SizedBox(height: 16),
            const Text(
              'ليس لديك متجر بعد',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'أنشئ متجرك لتصبح هويتك التجاريّة الرسميّة. كلّ منتجاتك سترتبط به.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateStoreScreen(),
                  ),
                );
                if (result == true) {
                  onRefresh();
                }
              },
              icon: const Icon(Icons.add_business),
              label: const Text('أنشئ متجري الآن'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// العرض الرئيسيّ — رأس قابل للطيّ + تبويبات ثلاثة
class _StoreView extends StatelessWidget {
  final Store store;
  final String Function(DateTime) dateFormatter;
  final Future<void> Function() onRefresh;
  const _StoreView({
    required this.store,
    required this.dateFormatter,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _CoverHeader(store: store)),
            SliverToBoxAdapter(child: _StoreInfoHeader(store: store)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                const TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.onSurfaceVariant,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  labelStyle:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  tabs: [
                    Tab(text: 'المنتجات'),
                    Tab(text: 'المزادات'),
                    Tab(text: 'عن المتجر'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _ProductsTab(),
              const _AuctionsTab(),
              _AboutTab(store: store, dateFormatter: dateFormatter),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmToggleActive(BuildContext context, Store store) async {
  final activating = !store.isActive;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(activating ? 'تفعيل المتجر' : 'إيقاف المتجر'),
      content: Text(
        activating
            ? 'سيصبح متجرك ومنتجاتك مرئية للجميع من جديد.'
            : 'سيتوقف ظهور متجرك ومنتجاته للزوار مؤقتًا، ويمكنك تفعيله من جديد في أي وقت.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('تراجع'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(activating ? 'تفعيل' : 'إيقاف'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  final auth = context.read<AuthProvider>();
  final storeProvider = context.read<StoreProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final result = await storeProvider.toggleActive(
    accessToken: auth.accessToken!,
    storeId: store.id,
    isActive: activating,
  );
  if (!result.success) {
    messenger.showSnackBar(
      SnackBar(content: Text(result.message), backgroundColor: AppColors.error),
    );
  }
}

// رأس المعلومات: الاسم + الحالة + زر التعديل + الإحصاءات
class _StoreInfoHeader extends StatelessWidget {
  final Store store;
  const _StoreInfoHeader({required this.store});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
          child: Column(
            children: [
              Text(
                store.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _confirmToggleActive(context, store),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: (store.isActive
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        store.isActive ? 'متجر نشط' : 'متوقّف',
                        style: TextStyle(
                          color: store.isActive
                              ? AppColors.primary
                              : AppColors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_outlined,
                        size: 12,
                        color: store.isActive
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      final storeProvider = context.read<StoreProvider>();
                      final navigator = Navigator.of(context);
                      final result = await navigator.push<bool>(
                        MaterialPageRoute(
                          builder: (_) => EditStoreScreen(store: store),
                        ),
                      );
                      if (result == true) {
                        await storeProvider.loadMyStore(
                            accessToken: auth.accessToken!);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text(
                      'تعديل المتجر',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ManageCouponsScreen(storeId: store.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.confirmation_number_outlined,
                        size: 18),
                    label: const Text(
                      'الكوبونات',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _StatColumn(
                    value: '${store.totalItems}', label: 'منتج'),
              ),
              _statDivider(),
              Expanded(
                child: _StatColumn(
                    value: '${store.totalActiveItems}', label: 'نشط'),
              ),
              _statDivider(),
              Expanded(
                child: _StatColumn(
                    value: '${store.createdAt.year}', label: 'انضمام'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

({Color color, String label}) _itemStatusInfo(String status) {
  switch (status) {
    case 'active':
      return (color: AppColors.primary, label: 'نشط');
    case 'draft':
      return (color: AppColors.onSurfaceVariant, label: 'مسوّدة');
    case 'sold':
      return (color: AppColors.error, label: 'مباع');
    default:
      return (color: AppColors.secondary, label: status);
  }
}

// تبويب المنتجات — منتجاتي الأصليّة + المنتجات التي أُمثّلها كمندوب
class _ProductsTab extends StatefulWidget {
  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  int? _openingItemId;

  Future<void> _openRepresentedItem(RepresentativeRequest r) async {
    if (_openingItemId != null) return;
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _openingItemId = r.item.id);
    try {
      final listing = await ItemService().fetchListingByItemId(
        accessToken: auth.accessToken!,
        itemId: r.item.id,
      );
      if (!mounted) return;
      if (listing == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('لا يوجد عرض سعر ثابت لهذا المنتج بعد'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailsScreen(
            listing: listing,
            representativeAssignmentId: r.id,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingItemId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().user?.id;
    return Consumer2<MyItemsProvider, RepresentativeRequestsProvider>(
      builder: (context, myItems, reps, _) {
        if (myItems.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final represented = reps.active
            .where((r) =>
                r.representative.id == currentUserId && r.canList)
            .toList();

        if (myItems.items.isEmpty && represented.isEmpty) {
          return const _EmptyState(
            icon: Icons.inventory_2_outlined,
            message: 'لا توجد منتجات في متجرك بعد',
          );
        }

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (myItems.items.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(title: 'منتجاتي'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = myItems.items[index];
                      return _StoreProductCard(
                        title: item.title,
                        quantity: item.quantity,
                        imageUrl: item.firstImage,
                        status: _itemStatusInfo(item.status),
                      );
                    },
                    childCount: myItems.items.length,
                  ),
                ),
              ),
            ],
            if (represented.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(title: 'منتجات أُمثّلها كمندوب'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final r = represented[index];
                      return _StoreProductCard(
                        title: r.item.title,
                        quantity: r.item.quantity,
                        imageUrl: r.item.firstImage,
                        status: _itemStatusInfo(r.item.status),
                        repBadgeLabel: 'مندوب',
                        isLoading: _openingItemId == r.item.id,
                        onTap: () => _openRepresentedItem(r),
                      );
                    },
                    childCount: represented.length,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}

// تبويب المزادات
class _AuctionsTab extends StatefulWidget {
  const _AuctionsTab();

  @override
  State<_AuctionsTab> createState() => _AuctionsTabState();
}

class _AuctionsTabState extends State<_AuctionsTab> {
  final _service = AuctionService();
  Timer? _ticker;
  List<Auction> _auctions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchMyAuctions(accessToken: token);
      if (mounted) {
        setState(() {
          _auctions = list;
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_auctions.isEmpty) {
      return const _EmptyState(
        icon: Icons.gavel_outlined,
        message: 'لا توجد مزادات في متجرك بعد',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _auctions.length,
        itemBuilder: (context, i) => _StoreAuctionCard(
          auction: _auctions[i],
          onEdited: _load,
        ),
      ),
    );
  }
}

// تبويب عن المتجر — حقول Store الحقيقيّة
class _AboutTab extends StatelessWidget {
  final Store store;
  final String Function(DateTime) dateFormatter;
  const _AboutTab({required this.store, required this.dateFormatter});

  Future<void> _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsapp(String phone) async {
    final uri = Uri.parse('https://wa.me/${toWhatsappDigits(phone)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final divider = Divider(
      height: 24,
      color: AppColors.outlineVariant.withValues(alpha: 0.4),
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        if (store.description.isNotEmpty) ...[
          const Text(
            'وصف المتجر',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            store.description,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 15,
              height: 1.7,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.person_outline,
                label: 'المالك',
                value: store.user.username,
              ),
              divider,
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'تاريخ الإنشاء',
                value: dateFormatter(store.createdAt),
              ),
              divider,
              _InfoRow(
                icon: Icons.inventory_2_outlined,
                label: 'إجمالي المنتجات',
                value: '${store.totalItems}',
              ),
              if (store.defaultLocation != null &&
                  store.defaultLocation!.isNotEmpty) ...[
                divider,
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'الموقع',
                  value: store.defaultLocation!,
                ),
              ],
              if (store.phoneNumber.isNotEmpty) ...[
                divider,
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'رقم الهاتف',
                  value: store.phoneNumber,
                  onTap: () => _launchPhone(store.phoneNumber),
                ),
              ],
              if (store.whatsappNumber.isNotEmpty) ...[
                divider,
                _InfoRow(
                  icon: Icons.chat_outlined,
                  label: 'واتساب',
                  value: store.whatsappNumber,
                  onTap: () => _launchWhatsapp(store.whatsappNumber),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// بطاقة مزاد في متجري
class _StoreAuctionCard extends StatelessWidget {
  final Auction auction;
  final Future<void> Function() onEdited;
  const _StoreAuctionCard({required this.auction, required this.onEdited});

  static const _gold = Color(0xFFF7C948);

  String _formatRemaining() {
    final now = DateTime.now();
    int secs;
    if (auction.isUpcoming) {
      secs = auction.startTime.difference(now).inSeconds;
      if (secs <= 0) return 'يبدأ الآن';
    } else if (auction.isActive) {
      secs = auction.endTime.difference(now).inSeconds;
      if (secs <= 0) return 'انتهى';
    } else {
      return 'انتهى';
    }
    final d = secs ~/ 86400;
    final h = (secs % 86400) ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (d > 0) return '$d يوم $h س';
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
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

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AuctionDetailsScreen(auction: auction),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.25),
          ),
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
            // صورة المنتج
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
              child: Stack(
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: auction.item.firstImage != null
                        ? AppNetworkImage(
                            auction.item.firstImage!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.surfaceContainer,
                              child: const Icon(Icons.broken_image,
                                  color: AppColors.onSurfaceVariant),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceContainer,
                            child: const Icon(Icons.gavel,
                                color: AppColors.onSurfaceVariant),
                          ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // التفاصيل
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            auction.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        if (auction.bidCount == 0 && !auction.isEnded)
                          InkWell(
                            onTap: () async {
                              final result = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EditAuctionScreen(auction: auction),
                                ),
                              );
                              if (result == true) await onEdited();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.edit_outlined,
                                  size: 16, color: AppColors.secondary),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'IQD',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatNum(auction.currentPrice),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!auction.isEnded) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: auction.isActive
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 12,
                                  color: auction.isActive
                                      ? AppColors.primary
                                      : AppColors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  _formatRemaining(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: auction.isActive
                                        ? AppColors.primary
                                        : AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${auction.bidCount} مزايد',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.groups,
                                size: 14,
                                color: AppColors.onSurfaceVariant),
                          ],
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
    );
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
          Icon(icon, size: 64, color: AppColors.outline),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// شريط التبويبات الملتصق
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
    return Container(color: AppColors.surface, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

// الغلاف الداكن + الشعار المتراكب
class _CoverHeader extends StatelessWidget {
  final Store store;
  const _CoverHeader({required this.store});

  @override
  Widget build(BuildContext context) {
    final cover = store.fullCoverUrl;
    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClipRect(
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover != null
                      ? AppNetworkImage(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _gradientBg(),
                        )
                      : _gradientBg(),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _circleIcon(
                            context,
                            Icons.share,
                            () => shareLink(
                              context,
                              text: DeepLinkConfig.storeLink(store.id),
                              subject: store.name,
                            ),
                          ),
                          _circleIcon(
                            context,
                            Icons.arrow_forward_ios,
                            () => Navigator.maybePop(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceContainerLowest,
                border: Border.all(
                  color: AppColors.surfaceContainerLowest,
                  width: 5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: store.fullLogoUrl != null
                    ? AppNetworkImage(
                        store.fullLogoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _logoFallback(),
                      )
                    : _logoFallback(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoFallback() {
    return Container(
      color: AppColors.surfaceContainer,
      child: const Icon(Icons.storefront,
          size: 48, color: AppColors.onSurfaceVariant),
    );
  }

  Widget _gradientBg() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.secondary, AppColors.onSurface],
        ),
      ),
    );
  }

  Widget _circleIcon(
      BuildContext context, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.onSurface),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;
  const _StatColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label:',
            style: const TextStyle(
                color: AppColors.onSurfaceVariant, fontSize: 14)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: onTap != null ? AppColors.primary : AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

// بطاقة منتج بنظام "الشورجة"
class _StoreProductCard extends StatelessWidget {
  final String title;
  final int quantity;
  final String? imageUrl;
  final ({Color color, String label}) status;
  final String? repBadgeLabel;
  final bool isLoading;
  final VoidCallback? onTap;
  const _StoreProductCard({
    required this.title,
    required this.quantity,
    required this.imageUrl,
    required this.status,
    this.repBadgeLabel,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: imageUrl != null
                        ? AppNetworkImage(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: AppColors.surfaceContainer,
                              child: const Icon(Icons.broken_image,
                                  color: AppColors.onSurfaceVariant),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceContainer,
                            child: const Icon(Icons.image,
                                color: AppColors.onSurfaceVariant),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (repBadgeLabel != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        repBadgeLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الكمية: $quantity',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}