import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../config/deep_link_config.dart';
import '../models/listing.dart';
import '../models/representative_reservation.dart';
import '../models/coupon_collection.dart';
import '../providers/auth_provider.dart';
import '../providers/review_provider.dart';
import '../services/analytics_service.dart';
import '../services/item_service.dart';
import '../services/representative_service.dart';
import '../services/reservation_service.dart';
import '../services/store_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/share_helper.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/product_card.dart';
import '../widgets/report_bottom_sheet.dart';
import '../widgets/reviews/review_list_section.dart';
import 'representative_request_screen.dart';
import 'reservations_screen.dart';
import 'resale_request_screen.dart';
import 'store_profile_screen.dart' show VisitStoreButton;
import '../features/location/screens/location_picker_sheet.dart';
import 'reservation_sheet.dart';
import 'make_offer_sheet.dart';

class ProductDetailsScreen extends StatefulWidget {
  final FixedListing listing;
  // معرّف تكليف المندوب — عند تمريره يتم إنشاء الحجز عبر
  // /representatives/{id}/create_reservation_for_buyer/ بدل المسار العادي،
  // ليُنسب البيع للمندوب وتُحتسب عمولته.
  final int? representativeAssignmentId;
  // تمرَّر عند القدوم من "احجز بهذا السعر" على عرض مقبول بالشات — تفتح شاشة
  // الحجز مباشرة بكمية وسعر مقفَلين على العرض.
  final int? acceptedOfferMessageId;
  final double? acceptedOfferAmount;
  final int? acceptedOfferQuantity;
  const ProductDetailsScreen({
    super.key,
    required this.listing,
    this.representativeAssignmentId,
    this.acceptedOfferMessageId,
    this.acceptedOfferAmount,
    this.acceptedOfferQuantity,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  bool _isFavorite = false;
  bool _isReserving = false;
  int _quantity = 1;
  LocationPickerResult? _deliveryResult;
  int? _offerMessageId;

  List<CouponCollection> _eligibleCoupons = [];
  CouponCollection? _selectedCoupon;

  AcceptedOffer? get _acceptedOffer {
    final id = widget.acceptedOfferMessageId;
    final amount = widget.acceptedOfferAmount;
    final qty = widget.acceptedOfferQuantity;
    if (id == null || amount == null || qty == null) return null;
    return AcceptedOffer(messageId: id, quantity: qty, amount: amount);
  }

  double get _currentTotal => widget.listing.price * _quantity;

  @override
  void initState() {
    super.initState();
    AppAnalytics.viewItem(
      itemId: widget.listing.item.id.toString(),
      itemName: widget.listing.item.title,
      contentType: 'listing',
    );
    if (_acceptedOffer != null) {
      // Skip the normal "reserve" tap — go straight into the locked
      // quantity/price sheet for the accepted offer.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openReservationSheet());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEligibleCoupons());
    }
  }

  Future<void> _loadEligibleCoupons() async {
    // Coupon redemption isn't wired into the representative reservation
    // flow on the backend yet, so don't offer it in that mode.
    if (widget.representativeAssignmentId != null) return;
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    try {
      final store = await StoreService().fetchStoreByUsername(
        accessToken: token,
        username: widget.listing.item.owner.username,
      );
      if (store == null || !mounted) return;
      final myCoupons = await StoreService().fetchMyCoupons(accessToken: token);
      if (!mounted) return;
      setState(() {
        _eligibleCoupons = myCoupons
            .where((c) => c.coupon.store == store.id && c.isUsable)
            .toList();
      });
    } catch (_) {
      // Coupons are a bonus feature — silently ignore failures.
    }
  }

  Future<void> _openCouponPicker() async {
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CouponPickerSheet(
        coupons: _eligibleCoupons,
        currentTotal: _currentTotal,
        selected: _selectedCoupon,
      ),
    );
    if (picked == null) return;
    setState(() => _selectedCoupon = picked is CouponCollection ? picked : null);
  }

  void _clearCouponIfNoLongerEligible() {
    final coupon = _selectedCoupon;
    if (coupon != null && _currentTotal < coupon.coupon.minOrderAmount) {
      _selectedCoupon = null;
    }
  }

  /// Opens the small "quantity + delivery location" sheet shown when the
  /// buyer taps "احجز"; on confirm, updates state and performs the reserve.
  Future<void> _openReservationSheet() async {
    final result = await showReservationSheet(
      context,
      listing: widget.listing,
      initialQuantity: _quantity,
      initialDelivery: _deliveryResult,
      acceptedOffer: _acceptedOffer,
    );
    if (result == null || !mounted) return;
    setState(() {
      _quantity = result.quantity;
      _deliveryResult = result.delivery;
      _offerMessageId = result.offerMessageId;
      _clearCouponIfNoLongerEligible();
    });
    await _reserve();
  }

  Future<void> _reserve() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isReserving = true);

    final assignmentId = widget.representativeAssignmentId;
    try {
      if (assignmentId != null) {
        final result = await RepresentativeService().createReservationForBuyer(
          accessToken: auth.accessToken!,
          representativeAssignmentId: assignmentId,
          request: CreateReservationRequest(
            itemId: widget.listing.item.id,
            quantity: _quantity,
            deliveryLocationId: _deliveryResult?.locationId,
          ),
        );
        if (!mounted) return;
        if (!result.success) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
        _showReservationSuccessDialog(
          deposit: result.reservation!.depositAmount.toStringAsFixed(0),
          total: result.reservation!.totalPrice.toStringAsFixed(0),
          expiresAt: result.reservation!.expiresAt,
          commissionAmount: result.reservation!.commissionAmount,
        );
      } else {
        final data = await ReservationService().createReservation(
          accessToken: auth.accessToken!,
          itemId: widget.listing.item.id,
          quantity: _quantity,
          couponCollectionId: _selectedCoupon?.id,
          deliveryLocationId: _deliveryResult?.locationId,
          offerMessageId: _offerMessageId,
        );
        if (!mounted) return;
        setState(() {
          _selectedCoupon = null;
          _offerMessageId = null;
        });
        final deposit = data['deposit_amount']?.toString() ?? '—';
        final total = data['total_price']?.toString() ?? '—';
        final expiresAt = data['expires_at'] as String?;
        _showReservationSuccessDialog(
          deposit: deposit,
          total: total,
          expiresAt: expiresAt != null ? DateTime.tryParse(expiresAt) : null,
        );
      }
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

  void _showReservationSuccessDialog({
    required String deposit,
    required String total,
    DateTime? expiresAt,
    double? commissionAmount,
  }) {
    final expiry = expiresAt?.toLocal().toString().substring(0, 16) ?? '—';
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: AppColors.success),
              SizedBox(width: 8),
              Text('تم الحجز بنجاح'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('المنتج: ${widget.listing.item.title}'),
              const SizedBox(height: 6),
              Text('الكمية: $_quantity'),
              Text('العربون: $deposit IQD'),
              Text('إجمالي السعر: $total IQD'),
              Text('ينتهي الحجز: $expiry'),
              if (commissionAmount != null) ...[
                const SizedBox(height: 6),
                Text(
                  'عمولة المندوب: ${commissionAmount.toStringAsFixed(0)} IQD',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
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
      ),
    );
  }

  String _conditionLabel(String c) {
    switch (c) {
      case 'new':
        return 'جديد';
      case 'like_new':
        return 'شبه جديد';
      case 'good':
        return 'جيّد';
      case 'used':
        return 'مستعمل';
      default:
        return c;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scope ReviewProvider to this screen's lifetime
    return ChangeNotifierProvider(
      create: (_) => ReviewProvider(widget.listing.item.id),
      child: _ProductDetailsBody(
        listing: widget.listing,
        isReserving: _isReserving,
        isFavorite: _isFavorite,
        quantity: _quantity,
        onReserve: _openReservationSheet,
        onToggleFavorite: () => setState(() => _isFavorite = !_isFavorite),
        conditionLabel: _conditionLabel,
        eligibleCoupons: _eligibleCoupons,
        selectedCoupon: _selectedCoupon,
        onPickCoupon: _openCouponPicker,
      ),
    );
  }
}

// ── Body widget sits below the provider so it can call context.read/watch ────

class _ProductDetailsBody extends StatelessWidget {
  final FixedListing listing;
  final bool isReserving;
  final bool isFavorite;
  final int quantity;
  final VoidCallback onReserve;
  final VoidCallback onToggleFavorite;
  final String Function(String) conditionLabel;
  final List<CouponCollection> eligibleCoupons;
  final CouponCollection? selectedCoupon;
  final VoidCallback onPickCoupon;

  const _ProductDetailsBody({
    required this.listing,
    required this.isReserving,
    required this.isFavorite,
    required this.quantity,
    required this.onReserve,
    required this.onToggleFavorite,
    required this.conditionLabel,
    required this.eligibleCoupons,
    required this.selectedCoupon,
    required this.onPickCoupon,
  });

  @override
  Widget build(BuildContext context) {
    final item = listing.item;
    final images = item.imageUrls;
    final isActive = item.status == 'active';
    final maxQty = item.quantity;
    final inStock = isActive && maxQty > 0;
    final lowStock = inStock && maxQty <= 5;
    final imageHeight = MediaQuery.of(context).size.width;
    final topInset = MediaQuery.of(context).padding.top;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isOwner = auth.user?.id == item.owner.id;

    // ── Discount maths ──────────────────────────────────────────────
    final price = listing.price;
    final double? original =
        (listing.originalPrice != null && listing.originalPrice! > price)
            ? listing.originalPrice
            : null;
    final int? discountPct =
        (listing.discountPercentage != null && listing.discountPercentage! > 0)
            ? listing.discountPercentage!.round()
            : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            // المحتوى القابل للتمرير
            ListView(
              padding: EdgeInsets.zero,
              children: [
                // ── معرض الصور مع الشارات ──────────────────────────
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _ImageCarousel(images: images, height: imageHeight),
                    if (discountPct != null || item.isDailyDeal)
                      PositionedDirectional(
                        top: topInset + 58,
                        start: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.isDailyDeal)
                              const _ImageBadge(
                                icon: Icons.bolt_rounded,
                                label: 'صفقة اليوم',
                                bg: AppColors.tertiaryContainer,
                                fg: AppColors.onTertiaryContainer,
                              ),
                            if (item.isDailyDeal && discountPct != null)
                              const SizedBox(height: 8),
                            if (discountPct != null)
                              _ImageBadge(
                                icon: Icons.sell_rounded,
                                label: 'خصم $discountPct٪',
                                bg: AppColors.primaryContainer,
                                fg: Colors.white,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                // ── لوحة المحتوى تعلو الصورة ─────────────────────────
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // مقبض السحب
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        // العنوان والسعر
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    text: '${formatNum(price)} ',
                                    style: const TextStyle(
                                      color: AppColors.primaryContainer,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    children: const [
                                      TextSpan(
                                        text: 'IQD',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (original != null)
                                  Text(
                                    '${formatNum(original)} IQD',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.outline,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // التقييم + المبيعات + الخصم + التوفّر
                        _buildMetaRow(
                          item.rating,
                          item.totalReviews,
                          item.soldCount,
                          discountPct,
                          inStock,
                          lowStock,
                          maxQty,
                        ),
                        const SizedBox(height: 24),
                        // الوصف
                        if (item.description.isNotEmpty) ...[
                          const _SectionTitle(title: 'الوصف'),
                          const SizedBox(height: 10),
                          Text(
                            item.description,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.8,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        // بطاقتا المواصفات (Bento)
                        Row(
                          children: [
                            Expanded(
                              child: _SpecCard(
                                icon: Icons.verified_outlined,
                                label: 'الحالة',
                                value: conditionLabel(item.condition),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SpecCard(
                                icon: (item.soldCount != null &&
                                        item.soldCount! > 0)
                                    ? Icons.shopping_bag_outlined
                                    : Icons.inventory_2_outlined,
                                label: (item.soldCount != null &&
                                        item.soldCount! > 0)
                                    ? 'المبيعات'
                                    : 'المتوفّر',
                                value: (item.soldCount != null &&
                                        item.soldCount! > 0)
                                    ? '${item.soldCount} مبيعة'
                                    : '$maxQty قطعة',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (inStock && !isOwner && lowStock) ...[
                          Text(
                            'متبقّي $maxQty قطع فقط — سارع بالطلب',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        // بطاقة الضمان
                        _WarrantyCard(warrantyDays: item.warrantyDays),
                        const SizedBox(height: 16),
                        // بطاقة العربون
                        if (listing.depositAmount > 0) ...[
                          _DepositCard(
                            amount: listing.depositAmount,
                            percentage: listing.depositPercentage,
                          ),
                          const SizedBox(height: 24),
                        ],
                        // بطاقة البائع
                        const _SectionTitle(title: 'البائع'),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppColors.surfaceContainer),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.secondary,
                                child: item.owner.username.isNotEmpty
                                    ? Text(
                                        item.owner.username[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : const Icon(Icons.storefront,
                                        color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            item.owner.username.isNotEmpty
                                                ? item.owner.username
                                                : 'بائع خاص',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.verified,
                                            size: 16, color: AppColors.primary),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'بائع موثّق على الشورجة',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              VisitStoreButton(
                                  ownerUsername: item.owner.username),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // تفاصيل التوصيل
                        const _SectionTitle(title: 'تفاصيل التوصيل'),
                        const SizedBox(height: 16),
                        const _DeliveryStep(
                          title: 'شحن سريع متوفر',
                          subtitle: 'يصل خلال ٢٤-٤٨ ساعة',
                          active: true,
                          showLine: true,
                        ),
                        const _DeliveryStep(
                          title: 'الدفع عند الاستلام',
                          subtitle: 'خدمة متوفّرة لهذا المنتج',
                          active: false,
                          showLine: false,
                        ),
                        const SizedBox(height: 20),
                        // منتجات مشابهة
                        _SimilarProducts(listingId: listing.id),
                      ],
                    ),
                  ),
                ),
                // ── قسم التقييمات ──────────────────────────────────
                const Divider(height: 1, color: AppColors.surfaceContainer),
                const SizedBox(height: 16),
                ReviewListSection(
                  itemId: item.id,
                  ownerId: item.owner.id,
                  averageRating: item.rating,
                  totalReviews: item.totalReviews ?? 0,
                ),
              ],
            ),
            // الأزرار العائمة في الأعلى
            Positioned(
              top: topInset + 8,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back_ios,
                    onTap: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      CircleIconButton(
                        icon: Icons.share_outlined,
                        onTap: () => shareLink(
                          context,
                          text: DeepLinkConfig.productLink(listing.id),
                          subject: item.title,
                        ),
                      ),
                      if (!isOwner) ...[
                        const SizedBox(width: 8),
                        CircleIconButton(
                          icon: Icons.flag_outlined,
                          onTap: () => showReportSheet(
                            context,
                            targetType: 'item',
                            targetId: item.id,
                            targetLabel: item.title,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      CircleIconButton(
                        icon: isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        iconColor: isFavorite
                            ? AppColors.error
                            : AppColors.onSurface,
                        onTap: onToggleFavorite,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        // الشريط السفليّ الثابت
        bottomNavigationBar: _BottomBar(
          listing: listing,
          quantity: quantity,
          isOwner: isOwner,
          inStock: inStock,
          isReserving: isReserving,
          onReserve: onReserve,
          eligibleCoupons: eligibleCoupons,
          selectedCoupon: selectedCoupon,
          onPickCoupon: onPickCoupon,
        ),
      ),
    );
  }

  // ── صف التقييم/المبيعات/الخصم/التوفّر ──────────────────────────────
  Widget _buildMetaRow(
    double? rating,
    int? totalReviews,
    int? soldCount,
    int? discountPct,
    bool inStock,
    bool lowStock,
    int maxQty,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rating != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 16, color: AppColors.gold),
                const SizedBox(width: 3),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                if (totalReviews != null && totalReviews > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($totalReviews)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (soldCount != null && soldCount > 0)
          Text(
            '$soldCount مبيعة',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (discountPct != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'وفّر $discountPct٪',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryContainer,
              ),
            ),
          ),
        // مؤشّر التوفّر
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: !inStock
                ? AppColors.errorContainer
                : lowStock
                    ? const Color(0xFFFFE6D6)
                    : const Color(0xFFE3F4E5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                !inStock
                    ? Icons.cancel_rounded
                    : lowStock
                        ? Icons.local_fire_department_rounded
                        : Icons.check_circle_rounded,
                size: 14,
                color: !inStock
                    ? AppColors.error
                    : lowStock
                        ? AppColors.primaryContainer
                        : AppColors.success,
              ),
              const SizedBox(width: 4),
              Text(
                !inStock
                    ? 'غير متوفّر'
                    : lowStock
                        ? 'متبقّي $maxQty'
                        : 'متوفّر',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: !inStock
                      ? AppColors.onErrorContainer
                      : lowStock
                          ? AppColors.primaryContainer
                          : AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===== الشريط السفليّ =====
class _BottomBar extends StatelessWidget {
  final FixedListing listing;
  final int quantity;
  final bool isOwner;
  final bool inStock;
  final bool isReserving;
  final VoidCallback onReserve;
  final List<CouponCollection> eligibleCoupons;
  final CouponCollection? selectedCoupon;
  final VoidCallback onPickCoupon;

  const _BottomBar({
    required this.listing,
    required this.quantity,
    required this.isOwner,
    required this.inStock,
    required this.isReserving,
    required this.onReserve,
    required this.eligibleCoupons,
    required this.selectedCoupon,
    required this.onPickCoupon,
  });

  @override
  Widget build(BuildContext context) {
    final total = listing.price * quantity;
    final canBuy = inStock && !isOwner;
    final coupon = selectedCoupon;
    final discount =
        coupon != null ? (coupon.coupon.amount > total ? total : coupon.coupon.amount) : 0.0;
    final finalTotal = total - discount;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceContainer)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canBuy) ...[
                if (eligibleCoupons.isNotEmpty) ...[
                  InkWell(
                    onTap: onPickCoupon,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: coupon != null
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.confirmation_number_outlined,
                              size: 18,
                              color: coupon != null
                                  ? AppColors.primary
                                  : AppColors.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              coupon != null
                                  ? 'كوبون ${coupon.coupon.code} (-${formatNum(discount)} IQD)'
                                  : 'لديك ${eligibleCoupons.length} كوبون متاح — اضغط للاستخدام',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: coupon != null
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (coupon != null)
                            const Icon(Icons.close_rounded,
                                size: 16, color: AppColors.onSurfaceVariant)
                          else
                            const Icon(Icons.chevron_left_rounded,
                                size: 18, color: AppColors.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (discount > 0) ...[
                      Text(
                        '${formatNum(total)} IQD',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.outline,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    RichText(
                      text: TextSpan(
                        text: '${formatNum(finalTotal)} ',
                        style: const TextStyle(
                          color: AppColors.primaryContainer,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        children: const [
                          TextSpan(
                            text: 'IQD',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$quantity × ${formatNum(listing.price)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed:
                            (canBuy && !isReserving) ? onReserve : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.surfaceContainerHigh,
                          disabledForegroundColor: AppColors.outline,
                          elevation: canBuy ? 2 : 0,
                          shadowColor:
                              AppColors.primaryContainer.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isReserving)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            else
                              const Icon(Icons.bookmark_add_outlined),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                isOwner
                                    ? 'هذا منتجك'
                                    : inStock
                                        ? 'احجز المنتج'
                                        : 'غير متوفّر حالياً',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (canBuy) ...[
                    const SizedBox(width: 12),
                    _SquareAction(
                      icon: Icons.local_offer_outlined,
                      label: 'قدّم عرضاً',
                      color: AppColors.success,
                      onTap: () => showMakeOfferSheet(context, listing: listing),
                    ),
                    const SizedBox(width: 12),
                    _SquareAction(
                      icon: Icons.badge_outlined,
                      label: 'مندوب',
                      color: AppColors.secondary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RepresentativeRequestScreen(
                              itemId: listing.item.id,
                              itemTitle: listing.item.title,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    _SquareAction(
                      icon: Icons.storefront_outlined,
                      label: 'إعادة بيع',
                      color: AppColors.tertiary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ResaleRequestScreen(
                              itemId: listing.item.id,
                              itemTitle: listing.item.title,
                              unitPrice: listing.item.price,
                              maxQuantity: listing.item.quantity,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== زر مربّع في الشريط السفليّ =====
class _SquareAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;
  const _SquareAction({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.6),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(label!, style: const TextStyle(fontSize: 9)),
            ],
          ],
        ),
      ),
    );
  }
}

// ===== شارة على الصورة =====
class _ImageBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  const _ImageBadge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== عنوان قسم بشريط لوني =====
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

// ===== بطاقة الضمان =====
class _WarrantyCard extends StatelessWidget {
  final int warrantyDays;
  const _WarrantyCard({required this.warrantyDays});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            AppColors.secondaryContainer.withValues(alpha: 0.55),
            AppColors.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.secondaryContainer.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: AppColors.secondary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    text: 'ضمان ',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                    children: [
                      TextSpan(
                        text: formatDaysAr(warrantyDays),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'مبلغك محفوظ بأمان حتى تتأكد من المنتج، ويُحرَّر للبائع '
                  'تلقائياً إن لم تُبلغ عن مشكلة خلال هذه المدة.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== بطاقة العربون =====
class _DepositCard extends StatelessWidget {
  final double amount;
  final double percentage;
  const _DepositCard({required this.amount, required this.percentage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            AppColors.tertiaryFixed.withValues(alpha: 0.55),
            AppColors.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.tertiaryContainer.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.tertiaryContainer.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.savings_outlined,
                color: AppColors.tertiary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    text: 'احجزه بعربون ',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                    children: [
                      TextSpan(
                        text: '${formatNum(amount)} IQD',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'عربون ${percentage.round()}٪ — والباقي يُدفع عند الاستلام',
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
    );
  }
}

// ===== منتجات مشابهة =====
class _SimilarProducts extends StatefulWidget {
  final int listingId;
  const _SimilarProducts({required this.listingId});

  @override
  State<_SimilarProducts> createState() => _SimilarProductsState();
}

class _SimilarProductsState extends State<_SimilarProducts> {
  late Future<List<FixedListing>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FixedListing>> _load() {
    final accessToken = context.read<AuthProvider>().accessToken;
    if (accessToken == null) return Future.value(const []);
    return ItemService().fetchSimilarListings(
      accessToken: accessToken,
      listingId: widget.listingId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FixedListing>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSection(child: _buildLoadingRow());
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return _buildSection(child: _buildItemsRow(items));
      },
    );
  }

  Widget _buildSection({required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'منتجات مشابهة'),
        const SizedBox(height: 14),
        SizedBox(height: 300, child: child),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildItemsRow(List<FixedListing> items) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, i) => SizedBox(
        width: 165,
        child: ProductCard(listing: items[i]),
      ),
    );
  }

  Widget _buildLoadingRow() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, _) => Container(
        width: 165,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

// ===== معرض الصور =====
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
        child: const Icon(Icons.image, size: 80, color: AppColors.outline),
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
            itemBuilder: (context, index) {
              return AppNetworkImage(
                widget.images[index],
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.surfaceContainer,
                  child: const Icon(Icons.broken_image,
                      size: 80, color: AppColors.outline),
                ),
              );
            },
          ),
          // عدّاد الصور
          if (widget.images.length > 1)
            PositionedDirectional(
              bottom: 40,
              end: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_current + 1}/${widget.images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          // النقاط
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

// ===== بطاقة مواصفة =====
class _SpecCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SpecCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.secondary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== خطوة توصيل =====
class _DeliveryStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final bool showLine;
  const _DeliveryStep({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.showLine,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? AppColors.primaryContainer
                      : AppColors.surfaceContainerHigh,
                  border: active
                      ? Border.all(
                          color: AppColors.primaryContainer
                              .withValues(alpha: 0.3),
                          width: 4)
                      : null,
                ),
              ),
              if (showLine)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.surfaceContainerHigh,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(bottom: showLine ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== ورقة اختيار الكوبون عند الحجز =====
class _CouponPickerSheet extends StatelessWidget {
  final List<CouponCollection> coupons;
  final double currentTotal;
  final CouponCollection? selected;

  const _CouponPickerSheet({
    required this.coupons,
    required this.currentTotal,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'اختر كوبوناً',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (selected != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline,
                    color: AppColors.error),
                title: const Text('بدون كوبون'),
                onTap: () => Navigator.pop(context, false),
              ),
            ...coupons.map((c) {
              final usable = currentTotal >= c.coupon.minOrderAmount;
              return ListTile(
                enabled: usable,
                leading: Icon(
                  Icons.confirmation_number_outlined,
                  color: usable ? AppColors.primary : AppColors.outline,
                ),
                title: Text('${c.coupon.code} — ${formatIqd(c.coupon.amount)}'),
                subtitle: Text(
                  usable
                      ? (c.coupon.minOrderAmount > 0
                          ? 'للطلبات فوق ${formatIqd(c.coupon.minOrderAmount)}'
                          : 'بدون حد أدنى للطلب')
                      : 'يتطلّب طلباً بقيمة ${formatIqd(c.coupon.minOrderAmount)} على الأقل',
                ),
                trailing: selected?.id == c.id
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary)
                    : null,
                onTap: usable ? () => Navigator.pop(context, c) : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}
