import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/listing.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../features/location/screens/location_picker_sheet.dart';

/// An accepted chat offer being redeemed — locks the sheet's quantity and
/// replaces the listing price with the negotiated total.
class AcceptedOffer {
  final int messageId;
  final int quantity;
  final double amount;
  const AcceptedOffer({
    required this.messageId,
    required this.quantity,
    required this.amount,
  });
}

class ReservationSheetResult {
  final int quantity;
  final LocationPickerResult? delivery;
  final int? offerMessageId;
  const ReservationSheetResult({
    required this.quantity,
    this.delivery,
    this.offerMessageId,
  });
}

/// Small sheet that gathers quantity + delivery location in one step,
/// shown when the buyer taps "احجز". Returns null if dismissed.
Future<ReservationSheetResult?> showReservationSheet(
  BuildContext context, {
  required FixedListing listing,
  required int initialQuantity,
  LocationPickerResult? initialDelivery,
  AcceptedOffer? acceptedOffer,
}) {
  AppAnalytics.beginCheckout(
    itemId: listing.item.id.toString(),
    value: acceptedOffer?.amount ?? listing.price * initialQuantity,
  );
  return showModalBottomSheet<ReservationSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: acceptedOffer == null,
    enableDrag: acceptedOffer == null,
    builder: (_) => _ReservationSheet(
      listing: listing,
      initialQuantity: initialQuantity,
      initialDelivery: initialDelivery,
      acceptedOffer: acceptedOffer,
    ),
  );
}

class _ReservationSheet extends StatefulWidget {
  final FixedListing listing;
  final int initialQuantity;
  final LocationPickerResult? initialDelivery;
  final AcceptedOffer? acceptedOffer;

  const _ReservationSheet({
    required this.listing,
    required this.initialQuantity,
    this.initialDelivery,
    this.acceptedOffer,
  });

  @override
  State<_ReservationSheet> createState() => _ReservationSheetState();
}

class _ReservationSheetState extends State<_ReservationSheet> {
  late int _quantity;
  LocationPickerResult? _delivery;
  bool _pickingLocation = false;

  bool get _isOffer => widget.acceptedOffer != null;
  int get _maxQty => widget.listing.item.quantity;
  double get _total =>
      widget.acceptedOffer?.amount ?? widget.listing.price * _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = _isOffer
        ? widget.acceptedOffer!.quantity
        : widget.initialQuantity.clamp(1, _maxQty < 1 ? 1 : _maxQty);
    _delivery = widget.initialDelivery;
  }

  void _inc() {
    if (!_isOffer && _quantity < _maxQty) setState(() => _quantity++);
  }

  void _dec() {
    if (!_isOffer && _quantity > 1) setState(() => _quantity--);
  }

  Future<void> _pickLocation() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    setState(() => _pickingLocation = true);
    final loc = await showLocationPickerSheet(
      context,
      token: token,
      title: 'اختر موقع التسليم',
    );
    if (!mounted) return;
    setState(() {
      _pickingLocation = false;
      if (loc != null) _delivery = LocationPickerResult.fromLocation(loc);
    });
  }

  void _confirm() {
    Navigator.pop(
      context,
      ReservationSheetResult(
        quantity: _quantity,
        delivery: _delivery,
        offerMessageId: widget.acceptedOffer?.messageId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.listing.item;
    final canConfirm = _delivery != null && !_pickingLocation;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: item.firstImage != null
                            ? AppNetworkImage(
                                item.firstImage!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _thumbFallback(),
                              )
                            : _thumbFallback(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تأكيد الحجز',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                if (_isOffer) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.tertiaryContainer.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.tertiaryContainer.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_offer_outlined,
                            size: 16, color: AppColors.tertiary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'سعر خاص متّفَق عليه بالشات — الكمية ثابتة حسب العرض',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.tertiary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Text(
                      'الكمية',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    _stepper(),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'مكان التسليم',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _deliveryCard(),
                const SizedBox(height: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'الإجمالي',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.onSurfaceVariant),
                      ),
                      const Spacer(),
                      Text(
                        _isOffer
                            ? 'عرض لـ $_quantity قطعة'
                            : '$_quantity × ${formatNum(widget.listing.price)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${formatNum(_total)} IQD',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: canConfirm ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceContainerHigh,
                      disabledForegroundColor: AppColors.outline,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'تأكيد الحجز',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (_delivery == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'اختر مكان التسليم للمتابعة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.image, color: AppColors.onSurfaceVariant),
      );

  Widget _stepper() {
    final canInc = !_isOffer && _quantity < _maxQty;
    final canDec = !_isOffer && _quantity > 1;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove_rounded, canDec ? _dec : null),
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text(
              '$_quantity',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface),
            ),
          ),
          _stepBtn(Icons.add_rounded, canInc ? _inc : null),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(
          icon,
          size: 19,
          color: enabled
              ? AppColors.primary
              : AppColors.outline.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _deliveryCard() {
    if (_pickingLocation) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_delivery == null) {
      return OutlinedButton.icon(
        onPressed: _pickLocation,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('اختر موقع التسليم'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return Container(
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
              _delivery!.address,
              style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: _pickLocation, child: const Text('تغيير')),
        ],
      ),
    );
  }
}
