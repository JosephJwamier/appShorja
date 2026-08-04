import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/live_session.dart';
import '../../services/live_session_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// "Show a product" controls shared by the store owner's broadcast screen
/// and a session moderator's viewer screen (see LiveViewerScreen) — both
/// grant the same powers backend-side (LiveSessionViewSet.catalog/show_item
/// /quick_show/quick_auction, all gated by _can_moderate_live_session, not
/// just IsStoreOwner), so the UI is identical for either caller.

/// Bottom sheet listing the store's own showable items — one tap shows
/// whichever one they pick, price/deposit pulled automatically.
Future<void> showLiveCatalogSheet(
  BuildContext context, {
  required int sessionId,
  required String accessToken,
  required LiveSessionService service,
  required ValueChanged<LiveSessionItem> onShown,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => LiveCatalogSheet(
      sessionId: sessionId,
      accessToken: accessToken,
      service: service,
      onShown: onShown,
    ),
  );
}

class LiveCatalogSheet extends StatefulWidget {
  final int sessionId;
  final String accessToken;
  final LiveSessionService service;
  final ValueChanged<LiveSessionItem> onShown;

  const LiveCatalogSheet({
    super.key,
    required this.sessionId,
    required this.accessToken,
    required this.service,
    required this.onShown,
  });

  @override
  State<LiveCatalogSheet> createState() => _LiveCatalogSheetState();
}

class _LiveCatalogSheetState extends State<LiveCatalogSheet> {
  List<LiveCatalogEntry>? _entries;
  String? _error;
  int? _showingItemId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.service.fetchCatalog(
        accessToken: widget.accessToken,
        sessionId: widget.sessionId,
      );
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _show(LiveCatalogEntry entry) async {
    setState(() => _showingItemId = entry.itemId);
    final result = await widget.service.showItem(
      accessToken: widget.accessToken,
      sessionId: widget.sessionId,
      itemId: entry.itemId,
    );
    if (!mounted) return;
    setState(() => _showingItemId = null);

    if (result.success) {
      final session = await widget.service.fetchLiveSessionDetail(
        accessToken: widget.accessToken,
        sessionId: widget.sessionId,
      );
      if (session.currentNowShowing != null) widget.onShown(session.currentNowShowing!);
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        if (_error != null) {
          return Center(child: Text(_error!));
        }
        if (_entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_entries!.isEmpty) {
          return const Center(child: Text('لا توجد منتجات في المتجر بعد'));
        }
        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: _entries!.length,
          itemBuilder: (context, index) {
            final entry = _entries![index];
            final busy = _showingItemId == entry.itemId;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: entry.imageUrl != null
                    ? CircleAvatar(backgroundImage: CachedNetworkImageProvider(entry.imageUrl!))
                    : const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                title: Text(entry.title, textAlign: TextAlign.right),
                subtitle: Text(
                  entry.suggestedPrice != null
                      ? '${formatIqd(entry.suggestedPrice!)} — الكمية ${entry.quantity}'
                      : 'بدون سعر مُدرج — الكمية ${entry.quantity}',
                  textAlign: TextAlign.right,
                ),
                trailing: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: entry.sessionStatus == 'now_showing' ? null : () => _show(entry),
                        child: Text(entry.sessionStatus == 'now_showing' ? 'معروض الآن' : 'اعرض'),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class LiveQuickShowInput {
  final String title;
  final double price;
  final double deposit;
  final int quantity;
  LiveQuickShowInput(this.title, this.price, this.deposit, this.quantity);
}

Future<LiveQuickShowInput?> showLiveQuickShowDialog(BuildContext context) {
  return showDialog<LiveQuickShowInput>(
    context: context,
    builder: (_) => const LiveQuickShowDialog(),
  );
}

/// "Show something never added to the app before" — title/price/deposit
/// only, a backing Item is created automatically by the backend.
class LiveQuickShowDialog extends StatefulWidget {
  const LiveQuickShowDialog({super.key});

  @override
  State<LiveQuickShowDialog> createState() => _LiveQuickShowDialogState();
}

class _LiveQuickShowDialogState extends State<LiveQuickShowDialog> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('عرض سريع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'لمنتج غير مُضاف للتطبيق من قبل — فقط اكتب الاسم والسعر والعربون',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
            ),
            TextField(
              controller: _priceController,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'السعر'),
            ),
            TextField(
              controller: _depositController,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'العربون'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الكمية المتوفرة'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final title = _titleController.text.trim();
              final price = double.tryParse(_priceController.text.trim());
              final deposit = double.tryParse(_depositController.text.trim());
              if (title.isEmpty || price == null || deposit == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('أكمل جميع الحقول بشكل صحيح')));
                return;
              }
              Navigator.pop(context, LiveQuickShowInput(title, price, deposit, _quantity));
            },
            child: const Text('اعرض الآن'),
          ),
        ],
      ),
    );
  }
}

class LiveQuickAuctionInput {
  final String title;
  final double startingPrice;
  final double minimumIncrement;
  final double bidDeposit;
  final int quantity;
  LiveQuickAuctionInput(
      this.title, this.startingPrice, this.minimumIncrement, this.bidDeposit, this.quantity);
}

Future<LiveQuickAuctionInput?> showLiveQuickAuctionDialog(BuildContext context) {
  return showDialog<LiveQuickAuctionInput>(
    context: context,
    builder: (_) => const LiveQuickAuctionDialog(),
  );
}

/// A 2-minute live auction — same one-tap spirit as quick-show, but viewers
/// bid instead of instantly reserving. Winner gets a pending Reservation to
/// complete, exactly like any other auction.
class LiveQuickAuctionDialog extends StatefulWidget {
  const LiveQuickAuctionDialog({super.key});

  @override
  State<LiveQuickAuctionDialog> createState() => _LiveQuickAuctionDialogState();
}

class _LiveQuickAuctionDialogState extends State<LiveQuickAuctionDialog> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _incrementController = TextEditingController(text: '5');
  final _depositController = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _incrementController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('مزاد سريع (دقيقتان)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يبدأ المزاد فوراً لمدة دقيقتين — المشاهدون يزايدون بدلاً من الحجز المباشر',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'اسم المنتج'),
              ),
              TextField(
                controller: _priceController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'سعر الافتتاح'),
              ),
              TextField(
                controller: _incrementController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الحد الأدنى لزيادة كل مزايدة'),
              ),
              TextField(
                controller: _depositController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'عربون المشاركة بالمزايدة'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الكمية المتوفرة'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                      ),
                      Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _quantity++),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final title = _titleController.text.trim();
              final price = double.tryParse(_priceController.text.trim());
              final increment = double.tryParse(_incrementController.text.trim());
              final deposit = double.tryParse(_depositController.text.trim());
              if (title.isEmpty || price == null || increment == null || deposit == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('أكمل جميع الحقول بشكل صحيح')));
                return;
              }
              Navigator.pop(context, LiveQuickAuctionInput(title, price, increment, deposit, _quantity));
            },
            child: const Text('ابدأ المزاد'),
          ),
        ],
      ),
    );
  }
}
