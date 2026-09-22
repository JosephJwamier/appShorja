import '../features/location/models/location_model.dart';
import '../utils/formatters.dart';
import 'delivery_order.dart';
import 'product.dart';
import 'user.dart';

class Reservation {
  final int id;
  final Product item;
  final User buyer;
  final int quantity;
  final double depositAmount;
  final double totalPrice;
  final String status;
  final DateTime reservedAt;
  final DateTime expiresAt;
  final DateTime? completedAt;
  final DateTime? buyerApprovedAt;
  final DateTime? paymentReleasedAt;
  final int timeRemaining;
  final bool canCancel;
  final bool canApprove;
  final bool buyerApproved;
  final String paymentStatus;
  final String paymentStatusMessage;
  final int? paymentStatusDaysRemaining;
  final bool isDepositOnly;
  final double amountCharged;
  final bool hasDispute;
  final int? disputeId;
  final String? disputeStatus;
  final String? proofScreenshotUrl;
  final LocationModel? deliveryLocation;
  final DeliveryOrder? deliveryOrder;
  final bool canSendToDelivery;
  final bool canRequestPaymentRelease;
  final double deliveryFee;
  final int warrantyDays;
  final int? auctionId;

  /// Platform commission frozen on this sale (taken from the seller at
  /// release) and what the seller actually nets after it and any
  /// representative's cut. Both come from the server; never recomputed here.
  final double platformCommissionPercent;
  final double platformCommissionAmount;
  final double sellerNet;

  /// True if this reservation settles an auction win — deposit_amount here
  /// is the bid deposit already paid while bidding, not a fresh charge.
  bool get isFromAuction => auctionId != null;

  /// True if this reservation is sitting still, waiting on [currentUserId]
  /// to do something about it right now — pay to complete it, confirm/refuse
  /// a delivered item, confirm the item after receiving it, or (seller) hand
  /// a paid order to the delivery company. Drives the "حجوزاتي" nav badge —
  /// mirrors the same gating the action buttons on each reservation card use
  /// (see _ReservationCard in reservations_screen.dart). canApprove and
  /// canSendToDelivery already come from the backend scoped to the buyer/
  /// seller respectively, so no extra role check is needed for those two.
  bool needsAction(int currentUserId) {
    final isBuyer = buyer.id == currentUserId;
    if (isBuyer && status == 'pending') return true;
    if (canApprove) return true;
    if (canSendToDelivery) return true;
    if (isBuyer && (deliveryOrder?.awaitingReceiptDecision ?? false)) {
      return true;
    }
    return false;
  }

  Reservation({
    required this.id,
    required this.item,
    required this.buyer,
    required this.quantity,
    required this.depositAmount,
    required this.totalPrice,
    required this.status,
    required this.reservedAt,
    required this.expiresAt,
    this.completedAt,
    this.buyerApprovedAt,
    this.paymentReleasedAt,
    required this.timeRemaining,
    required this.canCancel,
    required this.canApprove,
    required this.buyerApproved,
    required this.paymentStatus,
    this.paymentStatusMessage = '',
    this.paymentStatusDaysRemaining,
    this.isDepositOnly = false,
    this.amountCharged = 0,
    this.hasDispute = false,
    this.disputeId,
    this.disputeStatus,
    this.proofScreenshotUrl,
    this.deliveryLocation,
    this.deliveryOrder,
    this.canSendToDelivery = false,
    this.canRequestPaymentRelease = false,
    this.deliveryFee = 0,
    this.warrantyDays = 7,
    this.auctionId,
    this.platformCommissionPercent = 0,
    this.platformCommissionAmount = 0,
    this.sellerNet = 0,
  });

  /// Remaining amount to be collected in cash at delivery (only meaningful
  /// while status is 'completed' and [isDepositOnly] is true — i.e. before
  /// the sale is settled to 'confirmed').
  double get remainingCashOnDelivery => totalPrice - amountCharged;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final payment = json['payment_status'] as Map<String, dynamic>?;
    final dispute = json['dispute_status'] as Map<String, dynamic>?;
    final deliveryLocationJson =
        json['delivery_location'] as Map<String, dynamic>?;
    final deliveryOrderJson = json['delivery_order'] as Map<String, dynamic>?;
    final screenshot = json['proof_screenshot'] as String?;
    return Reservation(
      id: json['id'] as int,
      item: Product.fromJson(json['item'] as Map<String, dynamic>),
      buyer: User.fromJson(json['buyer'] as Map<String, dynamic>),
      quantity: json['quantity'] as int,
      depositAmount: double.parse(json['deposit_amount'] as String),
      totalPrice: double.parse(json['total_price'] as String),
      status: json['status'] as String,
      reservedAt: DateTime.parse(json['reserved_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      buyerApprovedAt: json['buyer_approved_at'] != null
          ? DateTime.parse(json['buyer_approved_at'] as String)
          : null,
      paymentReleasedAt: json['payment_released_at'] != null
          ? DateTime.parse(json['payment_released_at'] as String)
          : null,
      timeRemaining: json['time_remaining'] as int,
      canCancel: json['can_cancel'] as bool,
      canApprove: json['can_approve'] as bool,
      buyerApproved: json['buyer_approved'] as bool,
      paymentStatus: payment?['status'] as String? ?? 'pending',
      paymentStatusMessage: payment?['message'] as String? ?? '',
      paymentStatusDaysRemaining: payment?['days_remaining'] as int?,
      isDepositOnly: json['is_deposit_only'] as bool? ?? false,
      amountCharged: _toDouble(json['amount_charged']),
      hasDispute: json['has_dispute'] as bool? ?? false,
      disputeId: dispute?['id'] as int?,
      disputeStatus: dispute?['status'] as String?,
      proofScreenshotUrl: screenshot != null && screenshot.isNotEmpty
          ? fixMediaUrl(screenshot)
          : null,
      deliveryLocation: deliveryLocationJson != null
          ? LocationModel.fromJson(deliveryLocationJson)
          : null,
      deliveryOrder: deliveryOrderJson != null
          ? DeliveryOrder.fromJson(deliveryOrderJson)
          : null,
      canSendToDelivery: json['can_send_to_delivery'] as bool? ?? false,
      canRequestPaymentRelease:
          json['can_request_payment_release'] as bool? ?? false,
      deliveryFee: _toDouble(json['delivery_fee']),
      warrantyDays: json['warranty_days'] as int? ?? 7,
      auctionId: json['auction'] as int?,
      platformCommissionPercent: _toDouble(json['platform_commission_percent']),
      platformCommissionAmount: _toDouble(json['platform_commission_amount']),
      sellerNet: _toDouble(json['seller_net']),
    );
  }
}
