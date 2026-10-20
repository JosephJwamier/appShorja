import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../features/location/models/nearby_item_model.dart';
import '../models/listing.dart';
import '../providers/auth_provider.dart';
import '../services/item_service.dart';
import '../services/notification_service.dart';
import '../services/reservation_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../screens/representative_request_screen.dart';
import '../features/location/screens/location_picker_sheet.dart';
import '../widgets/circle_icon_button.dart';
import 'reservations_screen.dart';

class ItemFromMapScreen extends StatefulWidget {
  final NearbyItem item;

  const ItemFromMapScreen({super.key, required this.item});

  @override
  State<ItemFromMapScreen> createState() => _ItemFromMapScreenState();
}

class _ItemFromMapScreenState extends State<ItemFromMapScreen> {
  FixedListing? _listing;
  bool _loadingListing = true;
  bool _isReserving = false;
  bool _isFavorite = false;
  LocationPickerResult? _deliveryResult;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.item.isFavorited;
    _loadListing();
  }

  Future<void> _loadListing() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) {
      setState(() => _loadingListing = false);
      return;
    }
    try {
      final listing = await ItemService().fetchListingByItemId(
        accessToken: token,
        itemId: widget.item.id,
      );
      if (mounted) setState(() { _listing = listing; _loadingListing = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingListing = false);
    }
  }

  Future<void> _reserve() async {
    if (_listing == null) return;
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isReserving = true);
    try {
      final data = await ReservationService().createReservation(
        accessToken: auth.accessToken!,
        itemId: widget.item.id,
        quantity: 1,
        deliveryLocationId: _deliveryResult?.locationId,
      );
      if (!mounted) return;
      // أول حجز ناجح هو أول لحظة يصبح فيها إشعار الحجز مفيدًا فعليًا —
      // نطلب إذن الإشعارات هنا بدل أول فتحة للتطبيق.
      NotificationService.requestPermissionIfNeeded();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تم الحجز بنجاح'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المنتج: ${widget.item.title}'),
              const SizedBox(height: 6),
              Text('العربون: ${data['deposit_amount'] ?? '—'} IQD'),
              Text('إجمالي السعر: ${data['total_price'] ?? '—'} IQD'),
              if (data['expires_at'] != null)
                Text(
                  'ينتهي الحجز: ${DateTime.tryParse(data['expires_at'] as String)?.toLocal().toString().substring(0, 16) ?? '—'}',
                ),
              const SizedBox(height: 10),
              const Text(
                'لم يُخصم أي مبلغ بعد — أكمل الدفع (عربون أو كامل) من "حجوزاتي" قبل انتهاء المهلة.',
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لاحقاً'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReservationsScreen()),
                );
              },
              child: const Text('الذهاب لحجوزاتي'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isReserving = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    try {
      await ItemService().setFavorite(
        accessToken: auth.accessToken!,
        itemId: widget.item.id,
        favorited: next,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFavorite = !next);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _pickDeliveryLocation() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    final loc = await showLocationPickerSheet(
      context,
      token: token,
      title: 'اختر موقع التسليم',
    );
    if (loc == null || !mounted) return;
    setState(() => _deliveryResult = LocationPickerResult.fromLocation(loc));
  }

  String _conditionLabel(String c) {
    switch (c) {
      case 'new': return 'جديد';
      case 'like_new': return 'شبه جديد';
      case 'good': return 'جيّد';
      case 'fair': return 'مقبول';
      case 'poor': return 'مستعمل';
      default: return c;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final imageUrls = item.images.map((i) => fixMediaUrl(i.image)).toList();
    final auth = context.read<AuthProvider>();
    final isOwner = auth.user?.id == item.owner.id;
    final isAvailable = item.status == 'active';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              // ── صور المنتج ──────────────────────────────────────────────
              _ImageCarousel(
                images: imageUrls,
                height: MediaQuery.of(context).size.width,
              ),
              Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── العنوان والسعر ───────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_loadingListing)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            )
                          else if (_listing != null)
                            RichText(
                              text: TextSpan(
                                text:
                                    '${formatNum(_listing!.price)} ',
                                style: const TextStyle(
                                  color: AppColors.primaryContainer,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                                children: const [
                                  TextSpan(
                                      text: 'IQD',
                                      style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'غير مدرج',
                                style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ── المسافة ──────────────────────────────────────────
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              size: 15, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            item.distanceText,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ── الوصف ────────────────────────────────────────────
                      if (item.description.isNotEmpty) ...[
                        const Text('الوصف',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                          item.description,
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.7,
                              color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                      ],
                      // ── المواصفات ─────────────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _SpecCard(
                              icon: Icons.verified_outlined,
                              label: 'الحالة',
                              value: _conditionLabel(item.condition),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SpecCard(
                              icon: Icons.inventory_2_outlined,
                              label: 'الكمية',
                              value: '${item.quantity}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ── بطاقة البائع ─────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppColors.surfaceContainer),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: AppColors.secondary,
                              child: Text(
                                item.owner.username.characters.first
                                    .toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.owner.username,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('البائع',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── موقع التسليم ─────────────────────────────────────
                      const Text('موقع التسليم',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (_deliveryResult == null)
                        OutlinedButton.icon(
                          onPressed: _pickDeliveryLocation,
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('اختر موقع التسليم'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryFixed,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _deliveryResult!.address,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: _pickDeliveryLocation,
                                child: const Text('تغيير'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── أزرار التنقل العائمة ────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back_ios,
                  onTap: () => Navigator.pop(context),
                  size: 42,
                ),
                Row(
                  children: [
                    CircleIconButton(
                      icon: _isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      iconColor: _isFavorite
                          ? AppColors.error
                          : AppColors.onSurface,
                      onTap: _toggleFavorite,
                      size: 42,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),

      // ── شريط الحجز السفلي ────────────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.surfaceContainer)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: (_listing != null &&
                          isAvailable &&
                          !isOwner &&
                          !_isReserving)
                      ? _reserve
                      : null,
                  icon: _isReserving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bookmark_add_outlined),
                  label: Text(
                    isOwner
                        ? 'منتجك'
                        : !isAvailable
                            ? 'غير متوفّر'
                            : _loadingListing
                                ? 'جارٍ التحميل...'
                                : _listing == null
                                    ? 'غير متاح للحجز'
                                    : 'احجز المنتج',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
            if (!isOwner) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RepresentativeRequestScreen(
                        itemId: item.id,
                        itemTitle: item.title,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side:
                        const BorderSide(color: AppColors.secondary, width: 2),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 22),
                      SizedBox(height: 2),
                      Text('مندوب', style: TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── معرض الصور ──────────────────────────────────────────────────────────────
class _ImageCarousel extends StatefulWidget {
  final List<String> images;
  final double height;

  const _ImageCarousel({required this.images, required this.height});

  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Container(
        height: widget.height,
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.sell_rounded, size: 80, color: AppColors.outline),
      );
    }
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => AppNetworkImage(
              widget.images[i],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: AppColors.surfaceContainer,
                child: const Icon(Icons.broken_image,
                    size: 80, color: AppColors.outline),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: i == _current ? 24 : 6,
                    decoration: BoxDecoration(
                      color: i == _current
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── بطاقة مواصفة ────────────────────────────────────────────────────────────
class _SpecCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SpecCard(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFCFE2F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
