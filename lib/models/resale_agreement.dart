import 'user.dart';

class ResaleItem {
  final int id;
  final String name;
  final String? image;
  final double? price;
  final double? originalPrice;
  final double? discountPercentage;
  final int soldCount;
  final double rating;
  final String currency;

  const ResaleItem({
    required this.id,
    required this.name,
    this.image,
    this.price,
    this.originalPrice,
    this.discountPercentage,
    required this.soldCount,
    required this.rating,
    this.currency = '',
  });

  factory ResaleItem.fromJson(Map<String, dynamic> json) => ResaleItem(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    image: json['image'] as String?,
    price: json['price'] != null
        ? double.tryParse(json['price'].toString())
        : null,
    originalPrice: double.tryParse(json['original_price']?.toString() ?? ''),
    discountPercentage:
        double.tryParse(json['discount_percentage']?.toString() ?? ''),
    soldCount: json['sold_count'] as int? ?? 0,
    rating: double.tryParse(json['rating']?.toString() ?? '') ?? 0.0,
    currency: json['currency'] as String? ?? '',
  );
}

class ResaleAgreement {
  final int id;
  final ResaleItem item;
  final User owner;
  final User reseller;
  final String status;
  final int quantity;
  final double wholesalePricePerUnit;
  final double totalWholesalePrice;

  /// عمولة المنصة المقتطعة من البائع عند الموافقة، وما وصله بعدها.
  /// صفر و null قبل الموافقة أو من سيرفر أقدم.
  final double platformCommissionAmount;
  final double? ownerNetAmount;
  final ResaleItem? resultingItem;
  final String storageFeeType;
  final double? storageFeeAmount;
  final int storageFeePeriodDays;
  final double totalStorageFeesPaid;
  final DateTime? nextStorageFeeDue;
  final double dueStorageFee;
  final bool isStorageFeeDue;
  final int? durationDays;
  final DateTime? agreementStartDate;
  final DateTime? agreementEndDate;
  final int? daysRemaining;
  final bool isExpired;
  final String requestMessage;
  final String rejectionReason;
  final String notes;
  final DateTime initiatedAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final bool canApprove;
  final bool canReject;
  final bool canCancel;

  /// ثمنٌ لم يُحرَّر للبائع بعد، ومن يملك أي إجراء عليه (القواعد على
  /// الخادم: services/wholesale.py).
  final int heldQuantity;
  final double heldAmount;
  final DateTime? refundRequestedAt;
  final DateTime? handoverClaimedAt;

  /// نصّ التنبيه الذي يراه البائع مرّة واحدة قبل أول موافقة، أو null.
  final String? escrowNotice;

  /// هل يصل الثمن فوراً عند القبول (متجر جملة)؟ null من سيرفر أقدم.
  final bool? paysImmediately;
  final bool canConfirmReceived;
  final bool canRequestRefund;
  final bool canAcceptRefund;
  final bool canClaimHandover;

  const ResaleAgreement({
    required this.id,
    required this.item,
    required this.owner,
    required this.reseller,
    required this.status,
    required this.quantity,
    required this.wholesalePricePerUnit,
    required this.totalWholesalePrice,
    this.platformCommissionAmount = 0.0,
    this.ownerNetAmount,
    this.resultingItem,
    required this.storageFeeType,
    this.storageFeeAmount,
    required this.storageFeePeriodDays,
    this.totalStorageFeesPaid = 0.0,
    this.nextStorageFeeDue,
    required this.dueStorageFee,
    required this.isStorageFeeDue,
    this.durationDays,
    this.agreementStartDate,
    this.agreementEndDate,
    this.daysRemaining,
    required this.isExpired,
    required this.requestMessage,
    this.rejectionReason = '',
    this.notes = '',
    required this.initiatedAt,
    this.approvedAt,
    this.rejectedAt,
    this.completedAt,
    this.cancelledAt,
    required this.canApprove,
    required this.canReject,
    required this.canCancel,
    this.heldQuantity = 0,
    this.heldAmount = 0,
    this.refundRequestedAt,
    this.handoverClaimedAt,
    this.escrowNotice,
    this.paysImmediately,
    this.canConfirmReceived = false,
    this.canRequestRefund = false,
    this.canAcceptRefund = false,
    this.canClaimHandover = false,
  });

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isRejected => status == 'rejected';

  factory ResaleAgreement.fromJson(Map<String, dynamic> json) {
    DateTime? tryParse(dynamic v) =>
        v != null ? DateTime.tryParse(v as String) : null;

    return ResaleAgreement(
      id: json['id'] as int,
      item: ResaleItem.fromJson(json['item'] as Map<String, dynamic>),
      owner: User.fromJson(json['owner'] as Map<String, dynamic>),
      reseller: User.fromJson(json['reseller'] as Map<String, dynamic>),
      status: json['status'] as String? ?? 'pending',
      quantity: json['quantity'] as int? ?? 1,
      wholesalePricePerUnit: double.tryParse(
            json['wholesale_price_per_unit']?.toString() ?? '',
          ) ??
          0.0,
      totalWholesalePrice: double.tryParse(
            json['total_wholesale_price']?.toString() ?? '',
          ) ??
          0.0,
      platformCommissionAmount: double.tryParse(
            json['platform_commission_amount']?.toString() ?? '',
          ) ??
          0.0,
      ownerNetAmount:
          double.tryParse(json['owner_net_amount']?.toString() ?? ''),
      resultingItem: json['resulting_item'] != null
          ? ResaleItem.fromJson(json['resulting_item'] as Map<String, dynamic>)
          : null,
      storageFeeType: json['storage_fee_type'] as String? ?? 'none',
      storageFeeAmount: json['storage_fee_amount'] != null
          ? double.tryParse(json['storage_fee_amount'].toString())
          : null,
      storageFeePeriodDays: json['storage_fee_period_days'] as int? ?? 30,
      totalStorageFeesPaid:
          double.tryParse(json['total_storage_fees_paid']?.toString() ?? '') ??
              0.0,
      nextStorageFeeDue: tryParse(json['next_storage_fee_due']),
      dueStorageFee:
          double.tryParse(json['due_storage_fee']?.toString() ?? '') ?? 0.0,
      isStorageFeeDue: json['is_storage_fee_due'] as bool? ?? false,
      durationDays: json['duration_days'] as int?,
      agreementStartDate: tryParse(json['agreement_start_date']),
      agreementEndDate: tryParse(json['agreement_end_date']),
      daysRemaining: json['days_remaining'] as int?,
      isExpired: json['is_expired'] as bool? ?? false,
      requestMessage: json['request_message'] as String? ?? '',
      rejectionReason: json['rejection_reason'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      initiatedAt: DateTime.parse(json['initiated_at'] as String),
      approvedAt: tryParse(json['approved_at']),
      rejectedAt: tryParse(json['rejected_at']),
      completedAt: tryParse(json['completed_at']),
      cancelledAt: tryParse(json['cancelled_at']),
      canApprove: json['can_approve'] as bool? ?? false,
      canReject: json['can_reject'] as bool? ?? false,
      canCancel: json['can_cancel'] as bool? ?? false,
      heldQuantity: json['held_quantity'] as int? ?? 0,
      heldAmount: double.tryParse(json['held_amount']?.toString() ?? '') ?? 0.0,
      refundRequestedAt: tryParse(json['refund_requested_at']),
      handoverClaimedAt: tryParse(json['handover_claimed_at']),
      escrowNotice: json['escrow_notice'] as String?,
      paysImmediately: json['pays_immediately'] as bool?,
      canConfirmReceived: json['can_confirm_received'] as bool? ?? false,
      canRequestRefund: json['can_request_refund'] as bool? ?? false,
      canAcceptRefund: json['can_accept_refund'] as bool? ?? false,
      canClaimHandover: json['can_claim_handover'] as bool? ?? false,
    );
  }
}

class CreateTransferRequest {
  final int itemId;
  final int? variantId;
  final int quantity;
  final String storageFeeType;
  final double? storageFeeAmount;
  final int storageFeePeriodDays;
  final int? durationDays;
  final String requestMessage;
  final String notes;

  const CreateTransferRequest({
    required this.itemId,
    this.variantId,
    this.quantity = 1,
    this.storageFeeType = 'none',
    this.storageFeeAmount,
    this.storageFeePeriodDays = 30,
    this.durationDays,
    this.requestMessage = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    if (variantId != null) 'variant_id': variantId,
    'quantity': quantity,
    'storage_fee_type': storageFeeType,
    if (storageFeeType != 'none') 'storage_fee_amount': storageFeeAmount,
    'storage_fee_period_days': storageFeePeriodDays,
    if (durationDays != null) 'duration_days': durationDays,
    'request_message': requestMessage,
    'notes': notes,
  };
}
