import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/items_provider.dart';
import '../widgets/product_card.dart';
import 'add_item_screen.dart';
import 'my_items_screen.dart';
import 'auctions_screen.dart';
import 'received_requests_screen.dart';
import 'active_representatives_screen.dart';
import 'sent_requests_screen.dart';
import 'my_store_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<ItemsProvider>(context, listen: false);
    await provider.loadListings(accessToken: auth.accessToken!);
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    hintText: 'ابحث في العنوان أو الوصف...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                )
              : const Text('السوق'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.storefront), text: 'عروض'),
              Tab(icon: Icon(Icons.gavel), text: 'مزادات'),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              tooltip: _isSearching ? 'إغلاق البحث' : 'بحث',
              onPressed: _toggleSearch,
            ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.inventory_2),
                tooltip: 'منتجاتي',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyItemsScreen()),
                  );
                },
              ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.handshake_outlined),
                tooltip: 'طلبات المندوبيّة',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReceivedRequestsScreen(),
                    ),
                  );
                },
              ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.assignment_turned_in_outlined),
                tooltip: 'مندوبيّاتي النشطة',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ActiveRepresentativesScreen(),
                    ),
                  );
                },
              ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.outbox_outlined),
                tooltip: 'طلباتي المرسلة',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SentRequestsScreen(),
                    ),
                  );
                },
              ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.storefront_outlined),
                tooltip: 'متجري',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyStoreScreen()),
                  );
                },
              ),
            if (!_isSearching)
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'تسجيل الخروج',
                onPressed: () {
                  Provider.of<AuthProvider>(context, listen: false).logout(
                    notificationsProvider: Provider.of<NotificationsProvider>(
                        context,
                        listen: false),
                  );
                },
              ),
          ],
        ),
        body: TabBarView(
          children: [
            _FixedListingsView(onRefresh: _load, searchQuery: _searchQuery),
            AuctionsListView(searchQuery: _searchQuery),
          ],
        ),
        floatingActionButton: _isSearching
            ? null
            : FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddItemScreen()),
                  );
                },
                child: const Icon(Icons.add),
              ),
      ),
    );
  }
}

class _FixedListingsView extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final String searchQuery;
  const _FixedListingsView({
    required this.onRefresh,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ItemsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.listings.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.errorMessage != null && provider.listings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                provider.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        // التصفية المحلّيّة
        final query = searchQuery.trim().toLowerCase();
        final filtered = query.isEmpty
            ? provider.listings
            : provider.listings.where((l) {
                final title = l.item.title.toLowerCase();
                final desc = l.item.description.toLowerCase();
                return title.contains(query) || desc.contains(query);
              }).toList();

        if (filtered.isEmpty && provider.listings.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'لا توجد نتائج لـ "$searchQuery"',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }
        if (provider.listings.isEmpty) {
          return const Center(child: Text('لا توجد عروض بعد'));
        }
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              return ProductCard(listing: filtered[index]);
            },
          ),
        );
      },
    );
  }
}
