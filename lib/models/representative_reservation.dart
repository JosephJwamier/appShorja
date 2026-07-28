import 'product.dart';
import 'user.dart';
import '../features/location/models/location_model.dart';

class CreateReservationRequest {
  final int itemId;
  final int quantity;
  final int? deliveryLocationId;

  const CreateReservationRequest({
    required this.itemId,
    this.quantity = 1,
    this.deliveryLocationId,
  });

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'quantity': quantity,
    if (deliveryLocationId != null) 'delivery_location_id': deliveryLocationId,
  };
}

class RepresentativeInfo {
  final String username;
  final double commissionPercentage;
  final double commissionAmount;
  final String commissionStatus;

  const RepresentativeInfo({
    required this.username,
    required this.commissionPercentage,
    required this.commissionAmount,
    required this.commissionStatus,
  });

  factory RepresentativeInfo.fromJson(Map<String, dynamic> json) {
    return RepresentativeInfo(
      username: json['username'] as String? ?? '',
      commissionPercentage:
          double.tryParse(json['commission_percentage']?.toString() ?? '') ??
              0.0,
      commissionAmount:
          double.tryParse(json['commission_amount']?.toString() ?? '') ?? 0.0,
      commissionStatus: json['commission_status'] as String? ?? '',
    );
  }
}

class RepresentativeReservation {
  final int id;
  final Product item;
  final User buyer;
  final int quantity;
  final double depositAmount;
  final double totalPrice;
  final String status;
  final DateTime? reservedAt;
  final DateTime? expiresAt;
  final DateTime? completedAt;
  final bool buyerApproved;
  final DateTime? buyerApprovedAt;
  final bool sellerCancellationApproved;
  final bool paymentReleasedToSeller;
  final DateTime? paymentReleasedAt;
  final User representative;
  final int? representativeAssignmentId;
  final double commissionAmount;
  final bool commissionPaid;
  final DateTime? commissionPaidAt;
  final bool isTransferResale;
  final int? relatedTransfer;
  final double? originalOwnerCommission;
  final LocationModel? deliveryLocation;
  final int timeRemaining;
  final bool hasDispute;
  final String? disputeStatus;
  final bool canCancel;
  final bool canApprove;
  final String paymentStatus;
  final RepresentativeInfo representativeInfo;

  const RepresentativeReservation({
    required this.id,
    required this.item,
    required this.buyer,
    required this.quantity,
    required this.depositAmount,
    required this.totalPrice,
    required this.status,
    this.reservedAt,
    this.expiresAt,
    this.completedAt,
    required this.buyerApproved,
    this.buyerApprovedAt,
    required this.sellerCancellationApproved,
    required this.paymentReleasedToSeller,
    this.paymentReleasedAt,
    required this.representative,
    this.representativeAssignmentId,
    required this.commissionAmount,
    required this.commissionPaid,
    this.commissionPaidAt,
    required this.isTransferResale,
    this.relatedTransfer,
    this.originalOwnerCommission,
    this.deliveryLocation,
    required this.timeRemaining,
    required this.hasDispute,
    this.disputeStatus,
    required this.canCancel,
    required this.canApprove,
    required this.paymentStatus,
    required this.representativeInfo,
  });

  factory RepresentativeReservation.fromJson(Map<String, dynamic> json) {
    DateTime? tryDate(dynamic v) =>
        v != null ? DateTime.tryParse(v.toString()) : null;

    final data = json['data'] as Map<String, dynamic>;
    final repInfoJson = json['representative_info'] as Map<String, dynamic>?;

    return RepresentativeReservation(
      id: data['id'] as int,
      item: Product.fromJson(data['item'] as Map<String, dynamic>),
      buyer: User.fromJson(data['buyer'] as Map<String, dynamic>),
      quantity: data['quantity'] as int? ?? 1,
      depositAmount:
          double.tryParse(data['deposit_amount']?.toString() ?? '') ?? 0.0,
      totalPrice:
          double.tryParse(data['total_price']?.toString() ?? '') ?? 0.0,
      status: data['status'] as String? ?? 'pending',
      reservedAt: tryDate(data['reserved_at']),
      expiresAt: tryDate(data['expires_at']),
      completedAt: tryDate(data['completed_at']),
      buyerApproved: data['buyer_approved'] as bool? ?? false,
      buyerApprovedAt: tryDate(data['buyer_approved_at']),
      sellerCancellationApproved:
          data['seller_cancellation_approved'] as bool? ?? false,
      paymentReleasedToSeller:
          data['payment_released_to_seller'] as bool? ?? false,
      paymentReleasedAt: tryDate(data['payment_released_at']),
      representative:
          User.fromJson(data['representative'] as Map<String, dynamic>? ?? {}),
      representativeAssignmentId: data['representative_assignment'] as int?,
      commissionAmount:
          double.tryParse(data['commission_amount']?.toString() ?? '') ?? 0.0,
      commissionPaid: data['commission_paid'] as bool? ?? false,
      commissionPaidAt: tryDate(data['commission_paid_at']),
      isTransferResale: data['is_transfer_resale'] as bool? ?? false,
      relatedTransfer: data['related_transfer'] as int?,
      originalOwnerCommission: data['original_owner_commission'] != null
          ? double.tryParse(data['original_owner_commission'].toString())
          : null,
      deliveryLocation: data['delivery_location'] != null
          ? LocationModel.fromJson(
              data['delivery_location'] as Map<String, dynamic>)
          : null,
      timeRemaining: data['time_remaining'] as int? ?? 0,
      hasDispute: data['has_dispute'] as bool? ?? false,
      disputeStatus: data['dispute_status'] as String?,
      canCancel: data['can_cancel'] as bool? ?? false,
      canApprove: data['can_approve'] as bool? ?? false,
      paymentStatus: data['payment_status']?.toString() ?? '',
      representativeInfo: repInfoJson != null
          ? RepresentativeInfo.fromJson(repInfoJson)
          : const RepresentativeInfo(
              username: '',
              commissionPercentage: 0.0,
              commissionAmount: 0.0,
              commissionStatus: '',
            ),
    );
  }
}
