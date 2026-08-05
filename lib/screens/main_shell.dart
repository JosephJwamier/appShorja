import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/chats_provider.dart';
import '../providers/representative_requests_provider.dart';
import '../providers/transfers_provider.dart';
import '../theme/app_colors.dart';
import '../utils/refreshable_tab.dart';
import 'home_screen.dart';
import 'auctions_screen.dart';
import 'my_store_screen.dart';
import 'live/live_sessions_screen.dart';
import 'add_item_screen.dart';
import 'my_items_screen.dart';
import 'received_requests_screen.dart';
import 'sent_requests_screen.dart';
import 'active_representatives_screen.dart';
import 'reservations_screen.dart';
import 'disputes_screen.dart';
import 'account_settings_screen.dart';
import 'my_coupons_screen.dart';
import 'wallet_screen.dart';
import 'chats_list_screen.dart';
import 'store_chat_screen.dart';
import 'resale_agreements_screen.dart';
import '../features/location/screens/map_screen.dart';
import '../features/location/screens/my_locations_screen.dart';

/// مفتاح عام يتيح لأي شاشة مدفوعة فوق [MainShell] تبديل التبويب النشط
/// (مثلاً عند الضغط على شريط تنقّل مطابق ظاهر أسفل شاشة فرعية).
final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // مفاتيح لكل تبويب من التبويبات الخمسة التي تحمّل بيانات — تُستخدم في
  // _refreshTabAt للوصول إلى State الخاص بالتبويب (الذي يبقى حياً طوال
  // الجلسة بفضل IndexedStack أدناه) واستدعاء RefreshableTab.refreshTab عليه
  // كلّما أصبح هذا التبويب هو المختار، تماماً كما لو كانت شاشة مدفوعة حديثاً.
  final _homeKey = GlobalKey();
  final _auctionsKey = GlobalKey();
  final _liveKey = GlobalKey();
  final _chatsKey = GlobalKey();
  final _reservationsKey = GlobalKey();

  void jumpToTab(int index) {
    setState(() => _currentIndex = index);
    _refreshTabAt(index);
  }

  void _refreshTabAt(int index) {
    final key = switch (index) {
      0 => _homeKey,
      1 => _auctionsKey,
      2 => _liveKey,
      3 => _chatsKey,
      4 => _reservationsKey,
      _ => null,
    };
    final state = key?.currentState;
    if (state is RefreshableTab) (state as RefreshableTab).refreshTab();
  }

  @override
  void initState() {
    super.initState();
    // Fire-and-forget, mirrors ChatsProvider's load-on-shell-mount pattern:
    // populates the "incoming requests" badges (representative + resale)
    // as soon as the shell appears, without waiting for the user to open
    // either screen first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final token = context.read<AuthProvider>().accessToken;
      if (token == null) return;
      context
          .read<RepresentativeRequestsProvider>()
          .loadReceivedRequests(accessToken: token);
      context
          .read<TransfersProvider>()
          .loadTab(TransferTab.received, token: token);
    });
  }

  late final _tabs = [
    HomeScreen(key: _homeKey),
    AuctionsListView(key: _auctionsKey),
    LiveSessionsScreen(key: _liveKey),
    ChatsListScreen(key: _chatsKey),
    ReservationsScreen(key: _reservationsKey),
    const _AccountTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<ChatsProvider>().unreadMessagesCount;
    final pendingRequests =
        context.watch<RepresentativeRequestsProvider>().pendingReceivedCount +
        context.watch<TransfersProvider>().pendingReceivedCount;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _tabs),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              heroTag: 'mainShellAddItemFab',
              backgroundColor: AppColors.primary,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddItemScreen()),
                );
              },
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          _refreshTabAt(i);
        },
        backgroundColor: AppColors.surfaceContainerLowest,
        indicatorColor: AppColors.primaryContainer.withValues(alpha: 0.2),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppColors.primary),
            label: 'الرئيسية',
          ),
          const NavigationDestination(
            icon: Icon(Icons.gavel_outlined),
            selectedIcon: Icon(Icons.gavel, color: AppColors.primary),
            label: 'المزادات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv, color: AppColors.primary),
            label: 'البث المباشر',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              backgroundColor: AppColors.primary,
              textColor: AppColors.onPrimary,
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              backgroundColor: AppColors.primary,
              textColor: AppColors.onPrimary,
              child: const Icon(Icons.chat_bubble, color: AppColors.primary),
            ),
            label: 'المحادثات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark, color: AppColors.primary),
            label: 'حجوزاتي',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingRequests > 0,
              label: Text('$pendingRequests'),
              backgroundColor: AppColors.error,
              textColor: Colors.white,
              child: const Icon(Icons.person_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingRequests > 0,
              label: Text('$pendingRequests'),
              backgroundColor: AppColors.error,
              textColor: Colors.white,
              child: const Icon(Icons.person, color: AppColors.primary),
            ),
            label: 'الحساب',
          ),
        ],
      ),
    );
  }
}

// ===== تبويب الحساب =====
class _AccountTab extends StatelessWidget {
  const _AccountTab();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repPending =
        context.watch<RepresentativeRequestsProvider>().pendingReceivedCount;
    final resalePending =
        context.watch<TransfersProvider>().pendingReceivedCount;

    // التبويب مبنيّ داخل MainShell (الذي يُبنى بدون Directionality صريح، أي
    // LTR افتراضيًا) — لذا نغلّفه بـ RTL هنا صراحةً ليتطابق ترتيب العناصر
    // (وخاصةً سهم chevron_left) مع تصميم عربي سليم.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: AppColors.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccountSettingsScreen(),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(
                      Icons.support_agent_outlined,
                      color: AppColors.onSurfaceVariant,
                    ),
                    tooltip: 'التواصل مع الدعم',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StoreChatScreen(
                          isSupportChat: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primaryContainer,
                backgroundImage: auth.user?.fullAvatarUrl != null
                    ? CachedNetworkImageProvider(auth.user!.fullAvatarUrl!)
                    : null,
                child: auth.user?.fullAvatarUrl == null
                    ? Text(
                        (auth.user?.displayName ?? '?').characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                auth.user?.displayName ?? 'مستخدم',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _AccountTile(
              icon: Icons.storefront_outlined,
              label: 'متجري',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyStoreScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.inventory_2_outlined,
              label: 'منتجاتي',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyItemsScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.gavel_outlined,
              label: 'نزاعاتي',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DisputesScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.account_balance_wallet_outlined,
              label: 'محفظتي',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.confirmation_number_outlined,
              label: 'كوبوناتي',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyCouponsScreen()),
              ),
            ),
            const Divider(height: 32),
            const Padding(
              padding: EdgeInsets.only(right: 4, bottom: 8),
              child: Text(
                'المندوبيّة',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _AccountTile(
              icon: Icons.inbox_outlined,
              label: 'الطلبات الواردة',
              badgeCount: repPending,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReceivedRequestsScreen(),
                ),
              ),
            ),
            _AccountTile(
              icon: Icons.outbox_outlined,
              label: 'طلباتي المرسلة',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SentRequestsScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.handshake_outlined,
              label: 'المندوبيّات النشطة',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ActiveRepresentativesScreen(),
                ),
              ),
            ),
            const Divider(height: 32),
            const Padding(
              padding: EdgeInsets.only(right: 4, bottom: 8),
              child: Text(
                'إعادة البيع',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _AccountTile(
              icon: Icons.swap_horiz_rounded,
              label: 'اتفاقيات الإعادة',
              badgeCount: resalePending,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ResaleAgreementsScreen(),
                ),
              ),
            ),
            const Divider(height: 32),
            const Padding(
              padding: EdgeInsets.only(right: 4, bottom: 8),
              child: Text(
                'الاستكشاف',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _AccountTile(
              icon: Icons.map_rounded,
              label: 'الخريطة التفاعلية',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              ),
            ),
            _AccountTile(
              icon: Icons.location_on_outlined,
              label: 'مواقعي',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyLocationsScreen()),
              ),
            ),
            const Divider(height: 32),
            _AccountTile(
              icon: Icons.logout,
              label: 'تسجيل الخروج',
              color: AppColors.error,
              onTap: () => auth.logout(
                notificationsProvider: Provider.of<NotificationsProvider>(
                  context,
                  listen: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final int badgeCount;

  const _AccountTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasBadge = badgeCount > 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasBadge
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.surfaceContainer,
        ),
      ),
      child: ListTile(
        leading: Badge(
          isLabelVisible: hasBadge,
          label: Text('$badgeCount'),
          backgroundColor: AppColors.error,
          textColor: Colors.white,
          child: Icon(icon, color: color ?? AppColors.primary),
        ),
        title: Text(
          label,
          style: TextStyle(color: color ?? AppColors.onSurface),
        ),
        trailing: hasBadge
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeCount == 1 ? 'طلب جديد' : '$badgeCount طلبات جديدة',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_left,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              )
            : const Icon(
                Icons.chevron_left,
                color: AppColors.onSurfaceVariant,
              ),
        onTap: onTap,
      ),
    );
  }
}
