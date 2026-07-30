import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../features/location/models/location_model.dart';
import '../features/location/screens/widgets/delivery_location_widget.dart';
import '../models/reservation.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'disputes_screen.dart';
import 'file_dispute_screen.dart';
import 'print_delivery_label_screen.dart';

const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String _formatDateTime(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final period = l.hour < 12 ? 'ص' : 'م';
  final m = l.minute.toString().padLeft(2, '0');
  return '${l.day} ${_months[l.month - 1]} ${l.year} — $h:$m $period';
}

/// Full detail view of a single reservation — the buyer and seller land here
/// from the reservation card to see everything about the deal in one place:
/// the item, both parties, the live-stream proof screenshot (if reserved
/// during a live broadcast), the payment/settlement status, a timeline of
/// what happened when, delivery info, and the relevant actions.
class ReservationDetailScreen extends StatelessWidget {
  final Reservation reservation;
  final int currentUserId;
  final Future<void> Function(Reservation) onComplete;
  final Future<void> Function(Reservation) onCancel;
  final Future<void> Function(Reservation) onApprove;
  final Future<void> Function(Reservation) onRequestPaymentRelease;
  final Future<void> Function(Reservation) onSendToDelivery;
  final Future<void> Function(Reservation) onConfirmDeliveryReceipt;
  final Future<void> Function(Reservation) onRefuseDeliveryReceipt;
  final Future<void> Function(Reservation) onUpdateDeliveryLocation;
  final Future<void> Function() onRefresh;

  const ReservationDetailScreen({
    super.key,
    required this.reservation,
    required this.currentUserId,
    required this.onComplete,
    required this.onCancel,
    required this.onApprove,
    required this.onRequestPaymentRelease,
    required this.onSendToDelivery,
    required this.onConfirmDeliveryReceipt,
    required this.onRefuseDeliveryReceipt,
    required this.onUpdateDeliveryLocation,
    required this.onRefresh,
  });

  ({Color bg, Color fg, IconData icon, String label}) _statusStyle(
    String status,
  ) {
    switch (status) {
      case 'pending':
        return (
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
          icon: Icons.hourglass_top_rounded,
          label: 'بانتظار الدفع',
        );
      case 'completed':
        return (
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          icon: Icons.check_circle_outline,
          label: 'مدفوع — بانتظار التسليم',
        );
      case 'confirmed':
        return (
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
          icon: Icons.verified_outlined,
          label: 'مؤكَّد ومكتمل',
        );
      case 'cancelled':
        return (
          bg: const Color(0xFFFFEBEE),
          fg: AppColors.error,
          icon: Icons.cancel_outlined,
          label: 'ملغى',
        );
      case 'expired':
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.timer_off_outlined,
          label: 'منتهي المهلة',
        );
      case 'disputed':
        return (
          bg: const Color(0xFFFFEBEE),
          fg: AppColors.error,
          icon: Icons.gavel_outlined,
          label: 'نزاع مفتوح',
        );
      case 'refunded':
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.replay_outlined,
          label: 'مسترجَع',
        );
      default:
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.info_outline,
          label: status,
        );
    }
  }

  ({Color bg, Color fg, IconData icon}) _paymentStyle(String status) {
    switch (status) {
      case 'held':
        return (
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
          icon: Icons.lock_clock_outlined,
        );
      case 'approved_pending_release':
        return (
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
          icon: Icons.hourglass_bottom_rounded,
        );
      case 'released':
        return (
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          icon: Icons.verified_outlined,
        );
      case 'refunded':
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.replay_outlined,
        );
      default:
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.info_outline,
        );
    }
  }

  Future<void> _handleComplete(BuildContext context) async {
    await onComplete(reservation);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _handleCancel(BuildContext context) async {
    await onCancel(reservation);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _handleApprove(BuildContext context) async {
    await onApprove(reservation);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _handleSendToDelivery(BuildContext context) async {
    await onSendToDelivery(reservation);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _handleConfirmDeliveryReceipt(BuildContext context) async {
    await onConfirmDeliveryReceipt(reservation);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _handleRefuseDeliveryReceipt(BuildContext context) async {
    await onRefuseDeliveryReceipt(reservation);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _reportProblem(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FileDisputeScreen(reservation: reservation),
      ),
    );
    if (result == true) {
      await onRefresh();
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final isBuyer = r.buyer.id == currentUserId;
    final isSeller = r.item.owner.id == currentUserId;
    final canComplete = isBuyer && r.status == 'pending';
    // The backend flag alone doesn't check delivery-company progress — gate
    // it further here so the seller can only nudge the buyer once the item
    // has actually reached them (deliveryOrder.deliveredAt set), not while
    // it's still assigned/picked-up/in transit.
    final canRequestPaymentRelease = r.canRequestPaymentRelease &&
        (r.deliveryOrder == null || r.deliveryOrder!.deliveredAt != null);
    final awaitingCod = r.status == 'completed' &&
        r.isDepositOnly &&
        r.remainingCashOnDelivery > 0;
    final s = _statusStyle(r.status);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text(
            'تفاصيل الحجز',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroCard(s, awaitingCod),
                if (r.proofScreenshotUrl != null) ...[
                  const SizedBox(height: 14),
                  _buildProofCard(context),
                ],
                const SizedBox(height: 14),
                _buildPartiesCard(isBuyer, isSeller),
                const SizedBox(height: 14),
                _buildPaymentCard(awaitingCod),
                const SizedBox(height: 14),
                _buildTimelineCard(),
                if (r.deliveryLocation != null) ...[
                  const SizedBox(height: 14),
                  _buildDeliveryCard(context, isBuyer),
                ],
                if (r.deliveryOrder != null) ...[
                  const SizedBox(height: 14),
                  _buildDeliveryOrderCard(context),
                ],
                if (r.hasDispute) ...[
                  const SizedBox(height: 14),
                  _buildDisputeBanner(context),
                ],
                const SizedBox(height: 22),
                _buildActions(context, canComplete, canRequestPaymentRelease),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── بطاقة رأسيّة: صورة المنتج + الحالة + الأسعار ──────────────────────────
  Widget _buildHeroCard(
    ({Color bg, Color fg, IconData icon, String label}) s,
    bool awaitingCod,
  ) {
    final r = reservation;
    final image = r.item.firstImage;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceContainer),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 180,
                width: double.infinity,
                child: image != null
                    ? Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: s.bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.icon, size: 13, color: s.fg),
                      const SizedBox(width: 4),
                      Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: s.fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'رقم الحجز #${r.id}  ·  الكمية ${r.quantity}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _priceChip('عربون', formatIqd(r.depositAmount)),
                    const SizedBox(width: 8),
                    _priceChip('إجمالي', formatIqd(r.totalPrice)),
                    if (awaitingCod) ...[
                      const SizedBox(width: 8),
                      _priceChip(
                        'باقٍ كاش',
                        formatIqd(r.remainingCashOnDelivery),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── لقطة الحجز من البث المباشر ─────────────────────────────────────────
  Widget _buildProofCard(BuildContext context) {
    final r = reservation;
    final heroTag = 'reservation-screenshot-${r.id}';
    return _section(
      title: 'لقطة اللحظة من الحجز عبر البث المباشر',
      icon: Icons.videocam_outlined,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                _ScreenshotViewer(url: r.proofScreenshotUrl!, heroTag: heroTag),
            fullscreenDialog: true,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Hero(
                tag: heroTag,
                child: Image.network(
                  r.proofScreenshotUrl!,
                  width: double.infinity,
                  height: 190,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 190,
                    color: AppColors.surfaceContainerLow,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.outline,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.zoom_in_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── المشتري والبائع ─────────────────────────────────────────────────────
  Widget _buildPartiesCard(bool isBuyer, bool isSeller) {
    final r = reservation;
    return _section(
      title: 'أطراف الحجز',
      icon: Icons.people_outline,
      child: Column(
        children: [
          _personRow(
            roleLabel: 'المشتري',
            username: r.buyer.username,
            trustScore: r.buyer.trustScore,
            isYou: isBuyer,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.surfaceContainer),
          ),
          _personRow(
            roleLabel: 'البائع',
            username: r.item.owner.username,
            trustScore: r.item.owner.trustScore,
            isYou: isSeller,
          ),
        ],
      ),
    );
  }

  Widget _personRow({
    required String roleLabel,
    required String username,
    required double trustScore,
    required bool isYou,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.surfaceContainerLow,
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    roleLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (isYou) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'أنت',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                username,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (trustScore > 0)
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 15, color: AppColors.gold),
              const SizedBox(width: 2),
              Text(
                trustScore.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ── الدفع والمبالغ ───────────────────────────────────────────────────────
  Widget _buildPaymentCard(bool awaitingCod) {
    final r = reservation;
    final p = _paymentStyle(r.paymentStatus);
    return _section(
      title: 'الدفع',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('الكمية', '${r.quantity}'),
          _infoRow('العربون', formatIqd(r.depositAmount)),
          _infoRow('السعر الإجمالي', formatIqd(r.totalPrice)),
          if (r.deliveryFee > 0)
            _infoRow('أجور التوصيل', formatIqd(r.deliveryFee)),
          if (awaitingCod)
            _infoRow(
              'الباقي كاش عند التوصيل',
              formatIqd(r.remainingCashOnDelivery),
              highlight: true,
            ),
          if (r.paymentStatusMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(p.icon, size: 16, color: p.fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.paymentStatusMessage,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: highlight ? AppColors.primary : AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ── الجدول الزمني ────────────────────────────────────────────────────────
  Widget _buildTimelineCard() {
    final r = reservation;
    final settledAt = r.buyerApprovedAt ?? r.paymentReleasedAt;
    final settledLabel = r.buyerApprovedAt != null
        ? 'أكّد المشتري استلام المنتج'
        : r.paymentReleasedAt != null
        ? 'تحرير تلقائي للدفعة بعد 7 أيام بلا شكوى'
        : 'بانتظار تأكيد الاستلام';

    return _section(
      title: 'الجدول الزمني',
      icon: Icons.schedule_outlined,
      child: Column(
        children: [
          _timelineItem(
            icon: Icons.add_shopping_cart_outlined,
            label: 'تم إنشاء الحجز',
            date: r.reservedAt,
            done: true,
          ),
          _timelineItem(
            icon: Icons.payment_outlined,
            label: r.isDepositOnly
                ? 'دفع المشتري العربون'
                : 'دفع المشتري السعر كاملاً',
            date: r.completedAt,
            done: r.completedAt != null,
          ),
          _timelineItem(
            icon: Icons.verified_outlined,
            label: settledLabel,
            date: settledAt,
            done: settledAt != null,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _timelineItem({
    required IconData icon,
    required String label,
    DateTime? date,
    required bool done,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.surfaceContainerLow,
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: done ? AppColors.success : AppColors.onSurfaceVariant,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.surfaceContainer,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: done
                          ? AppColors.onSurface
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                  if (date != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatDateTime(date),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── موقع التوصيل ─────────────────────────────────────────────────────────
  Widget _buildDeliveryCard(BuildContext context, bool isBuyer) {
    final location = reservation.deliveryLocation!;
    // The address is only editable up until the seller hands the
    // reservation to the delivery company — deliveryOrder is set the
    // moment that happens (see ReservationViewSet.send_to_delivery /
    // update_delivery_location on the backend).
    final canEdit = isBuyer && reservation.deliveryOrder == null;
    return _section(
      title: 'موقع التوصيل',
      icon: Icons.place_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _DeliveryMapScreen(location: location),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    location.fullAddress.isNotEmpty
                        ? location.fullAddress
                        : location.addressLine1,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.map_outlined, size: 18, color: AppColors.primary),
                const Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (canEdit) ...[
            const Divider(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onUpdateDeliveryLocation(reservation),
                icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                label: const Text('تعديل عنوان التوصيل', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── تنبيه النزاع ─────────────────────────────────────────────────────────
  Widget _buildDisputeBanner(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DisputesScreen()),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gavel_outlined, size: 16, color: AppColors.error),
            const SizedBox(width: 6),
            const Text(
              'يوجد نزاع مفتوح على هذا الحجز — عرض التفاصيل',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── بطاقة طلب التوصيل ────────────────────────────────────────────────────
  Future<void> _openMaps(BuildContext context, String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح تطبيق الخرائط')),
      );
    }
  }

  Widget _addressRow(BuildContext context, String label, String name, String? mapsUrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
          Row(
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (mapsUrl != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _openMaps(context, mapsUrl),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _printDeliveryLabel(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrintDeliveryLabelScreen(order: reservation.deliveryOrder!),
      ),
    );
  }

  Widget _buildDeliveryOrderCard(BuildContext context) {
    final order = reservation.deliveryOrder!;
    final isReturn = order.direction == 'return';
    final isSeller = reservation.item.owner.id == currentUserId;
    final statusLabels = {
      'assigned': 'بانتظار استلام الشركة',
      'picked_up': isReturn ? 'استلمت الشركة المنتج منك' : 'استلمت الشركة المنتج من البائع',
      'delivered': order.cashCollected
          ? 'وصل المنتج وتم تحصيل الباقي نقداً — بانتظار تأكيدك'
          : 'وصل المنتج — بانتظار تأكيدك',
      'confirmed': 'تم التسليم وتأكيد الاستلام',
      'refused': 'تم رفض الاستلام',
      'failed': 'فشل التوصيل',
      'cancelled': 'ملغى',
    };
    return _section(
      title: isReturn ? 'إرجاع المنتج للبائع' : 'التوصيل',
      icon: Icons.local_shipping_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              statusLabels[order.status] ?? order.status,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          if (order.isMerged) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.tertiaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.merge_type, size: 14, color: AppColors.tertiary),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'مدموج مع حجوزات أخرى بنفس الرحلة — رسم توصيل واحد للجميع',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _addressRow(
            context,
            isReturn ? 'من (أنت)' : 'من (البائع)',
            order.fromName,
            order.fromMapsUrl,
          ),
          _addressRow(
            context,
            isReturn ? 'إلى (البائع)' : 'إلى (أنت)',
            order.toName,
            order.toMapsUrl,
          ),
          if (order.cashToCollect > 0)
            _infoRow(
              order.cashCollected ? 'كاش حصّلته الشركة ✓' : 'كاش تحصّله الشركة',
              formatIqd(order.cashToCollect),
              highlight: true,
            ),
          if (order.failureReason.isNotEmpty)
            _infoRow('السبب', order.failureReason),
          if (isSeller && !isReturn && order.status == 'assigned') ...[
            const Divider(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _printDeliveryLabel(context),
                icon: const Icon(Icons.print_outlined, size: 17),
                label: const Text(
                  'طباعة ملصق التوصيل',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── الإجراءات ────────────────────────────────────────────────────────────
  Widget _buildActions(
    BuildContext context,
    bool canComplete,
    bool canRequestPaymentRelease,
  ) {
    final r = reservation;
    final isBuyer = r.buyer.id == currentUserId;
    final buttons = <Widget>[];

    if (canComplete) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _handleComplete(context),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('إكمال الحجز'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (r.canApprove) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _handleApprove(context),
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('تم التأكد من المنتج'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (canRequestPaymentRelease) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => onRequestPaymentRelease(r),
          icon: const Icon(Icons.campaign_outlined, size: 18),
          label: const Text('طلب تحرير الدفعة من المشتري'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (r.canSendToDelivery) {
      buttons.add(
        FilledButton.icon(
          onPressed: () => _handleSendToDelivery(context),
          icon: const Icon(Icons.local_shipping_outlined, size: 18),
          label: const Text('إسناد التوصيل لشركة التوصيل'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    // awaitingReceiptDecision is purely status-based (no role check), so
    // isBuyer must be checked here or the seller sees it too.
    if (isBuyer && r.deliveryOrder?.awaitingReceiptDecision == true) {
      buttons.add(
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _handleConfirmDeliveryReceipt(context),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('تم الاستلام'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _handleRefuseDeliveryReceipt(context),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('رفض الاستلام'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!r.hasDispute && r.status == 'completed') {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _reportProblem(context),
          icon: const Icon(Icons.report_gmailerrorred_outlined, size: 18),
          label: const Text('الإبلاغ عن مشكلة'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.onSurfaceVariant,
            side: const BorderSide(color: AppColors.outlineVariant),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (r.canCancel) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => _handleCancel(context),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('إلغاء الحجز'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          buttons[i],
        ],
      ],
    );
  }

  Widget _priceChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.primaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    IconData? icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceContainer,
    child: const Icon(Icons.image, size: 36, color: AppColors.outline),
  );
}

// ── عارض اللقطة بملء الشاشة (تكبير/تصغير) ───────────────────────────────────
class _ScreenshotViewer extends StatelessWidget {
  final String url;
  final String heroTag;
  const _ScreenshotViewer({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── شاشة موقع التوصيل على الخريطة ───────────────────────────────────────────
class _DeliveryMapScreen extends StatelessWidget {
  final LocationModel location;
  const _DeliveryMapScreen({required this.location});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text(
            'موقع التوصيل',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DeliveryLocationWidget(location: location, mapHeight: 340),
          ),
        ),
      ),
    );
  }
}
