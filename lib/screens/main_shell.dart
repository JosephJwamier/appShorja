import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/chats_provider.dart';
import '../theme/app_colors.dart';
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

  void jumpToTab(int index) {
    setState(() => _currentIndex = index);
  }

  final _tabs = const [
    HomeScreen(),
    AuctionsListView(),
    LiveSessionsScreen(),
    ChatsListScreen(),
    ReservationsScreen(),
    _AccountTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<ChatsProvider>().unreadMessagesCount;

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
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
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
                child: Text(
                  (auth.user?.username ?? '?').characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                auth.user?.username ?? 'مستخدم',
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

  const _AccountTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.surfaceContainer),
      ),
      child: ListTile(
        leading: Icon(icon, color: color ?? AppColors.primary),
        title: Text(
          label,
          style: TextStyle(color: color ?? AppColors.onSurface),
        ),
        trailing: const Icon(
          Icons.chevron_left,
          color: AppColors.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}
