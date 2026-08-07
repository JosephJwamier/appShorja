import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/item_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../app_network_image.dart';

/// Bottom sheet for tagging a single product on a reel (shoppable video) —
/// reuses ItemService.fetchMyItems (the same "my products" fetch MyItemsScreen
/// uses) instead of inventing a new backend endpoint, since a reel can only
/// tag the posting store's own catalog. There's no server-side search query
/// param on that endpoint today, so filtering-as-you-type is done
/// client-side over the (typically small, single-store) result set — a
/// deliberate simplification for MVP rather than a new backend contract.
Future<Product?> showTagItemPickerSheet(
  BuildContext context, {
  required String accessToken,
  required int ownerId,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _TagItemPickerSheet(accessToken: accessToken, ownerId: ownerId),
  );
}

class _TagItemPickerSheet extends StatefulWidget {
  final String accessToken;
  final int ownerId;
  const _TagItemPickerSheet({required this.accessToken, required this.ownerId});

  @override
  State<_TagItemPickerSheet> createState() => _TagItemPickerSheetState();
}

class _TagItemPickerSheetState extends State<_TagItemPickerSheet> {
  final _service = ItemService();
  final _searchController = TextEditingController();
  List<Product> _items = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchMyItems(
        accessToken: widget.accessToken,
        ownerId: widget.ownerId,
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> get _filtered {
    if (_query.trim().isEmpty) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((p) => p.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('وسم منتج',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'ابحث في منتجاتك...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppColors.surfaceContainer,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildBody(scrollController)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(
        child: Text('لا توجد منتجات مطابقة', style: TextStyle(color: AppColors.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          onTap: () => Navigator.pop(context, item),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: item.firstImage != null
                  ? AppNetworkImage(item.firstImage!, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.surfaceContainer,
                      child: const Icon(Icons.inventory_2_outlined,
                          color: AppColors.onSurfaceVariant),
                    ),
            ),
          ),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: item.price != null ? Text(formatIqd(item.price!)) : null,
          trailing: const Icon(Icons.chevron_left, color: AppColors.onSurfaceVariant),
        );
      },
    );
  }
}
