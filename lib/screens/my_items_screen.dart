import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../services/item_service.dart';
import '../providers/auth_provider.dart';
import '../providers/my_items_provider.dart';
import 'create_listing_screen.dart';
import 'edit_item_screen.dart';
import 'edit_listing_price_screen.dart';

class MyItemsScreen extends StatefulWidget {
  const MyItemsScreen({super.key});

  @override
  State<MyItemsScreen> createState() => _MyItemsScreenState();
}

class _MyItemsScreenState extends State<MyItemsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final myItems = Provider.of<MyItemsProvider>(context, listen: false);
    if (auth.accessToken != null && auth.user != null) {
      await myItems.loadMyItems(
        accessToken: auth.accessToken!,
        ownerId: auth.user!.id,
      );
    }
  }

  ({Color color, String label}) _statusInfo(String status) {
    switch (status) {
      case 'active':
        return (color: Colors.green, label: 'نشط');
      case 'draft':
        return (color: Colors.grey, label: 'مسوّدة');
      case 'sold':
        return (color: Colors.red, label: 'مباع');
      default:
        return (color: Colors.blueGrey, label: status);
    }
  }

  Future<void> _confirmDelete(int itemId, String itemTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('حذف منتج'),
          content: Text(
            'هل تريد فعلاً حذف "$itemTitle"؟ لا يمكن التراجع عن هذا.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final service = ItemService();

    try {
      await service.deleteItem(accessToken: auth.accessToken!, itemId: itemId);

      if (!mounted) return;

      // أعد تحميل المنتجات
      await Provider.of<MyItemsProvider>(
        context,
        listen: false,
      ).loadMyItems(accessToken: auth.accessToken!, ownerId: auth.user!.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف "$itemTitle"'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الحذف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openPriceEditor(Product item) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditListingPriceScreen(product: item)),
    );
    if (updated == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('منتجاتي'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Consumer<MyItemsProvider>(
          builder: (context, myItems, child) {
            if (myItems.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (myItems.errorMessage != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 50,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 12),
                      Text(myItems.errorMessage!, textAlign: TextAlign.center),
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
            if (myItems.items.isEmpty) {
              return const Center(child: Text('لم ترفع أي منتج بعد'));
            }
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: myItems.items.length,
                itemBuilder: (context, index) {
                  final item = myItems.items[index];
                  final status = _statusInfo(item.status);
                  final isDraft = item.status == 'draft';

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: InkWell(
                      onTap: isDraft
                          ? () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CreateListingScreen(
                                    itemId: item.id,
                                    itemTitle: item.title,
                                  ),
                                ),
                              );
                              _load();
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 70,
                              height: 70,
                              child: item.firstImage != null
                                  ? Image.network(
                                      item.firstImage!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: Colors.grey[300],
                                        child: const Icon(Icons.broken_image),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[300],
                                      child: const Icon(Icons.image),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'الكمية: ${item.quantity}',
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: status.color.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      status.label,
                                      style: TextStyle(
                                        color: status.color,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isDraft)
                              IconButton(
                                icon: const Icon(
                                  Icons.sell_outlined,
                                  color: Colors.teal,
                                ),
                                tooltip: 'السعر والخصم',
                                onPressed: () => _openPriceEditor(item),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.blue,
                              ),
                              tooltip: 'تعديل',
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditItemScreen(product: item),
                                  ),
                                );
                                _load();
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              tooltip: 'حذف',
                              onPressed: () =>
                                  _confirmDelete(item.id, item.title),
                            ),
                            if (isDraft)
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
