import 'product.dart';
import 'user.dart';

class RepresentativeRequest {
  final int id;
  final Product item;
  final User owner;
  final User representative;
  final double commissionPercentage;
  final String status;
  final bool canList;
  final bool canNegotiate;
  final bool canCompleteSale;
  final String requestMessage;
  final String rejectionReason;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final bool canAccept;
  final bool canReject;
  final bool canCancel;

  RepresentativeRequest({
    required this.id,
    required this.item,
    required this.owner,
    required this.representative,
    required this.commissionPercentage,
    required this.status,
    required this.canList,
    required this.canNegotiate,
    required this.canCompleteSale,
    required this.requestMessage,
    required this.rejectionReason,
    required this.createdAt,
    this.acceptedAt,
    this.rejectedAt,
    this.completedAt,
    this.cancelledAt,
    required this.canAccept,
    required this.canReject,
    required this.canCancel,
  });

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  factory RepresentativeRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.parse(value as String);
    }

    return RepresentativeRequest(
      id: json['id'] as int,
      item: Product.fromJson(json['item'] as Map<String, dynamic>),
      owner: User.fromJson(json['owner'] as Map<String, dynamic>),
      representative:
          User.fromJson(json['representative'] as Map<String, dynamic>),
      commissionPercentage:
          double.parse(json['commission_percentage'] as String),
      status: json['status'] as String,
      canList: json['can_list'] as bool? ?? false,
      canNegotiate: json['can_negotiate'] as bool? ?? false,
      canCompleteSale: json['can_complete_sale'] as bool? ?? false,
      requestMessage: json['request_message'] as String? ?? '',
      rejectionReason: json['rejection_reason'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: parseDate(json['accepted_at']),
      rejectedAt: parseDate(json['rejected_at']),
      completedAt: parseDate(json['completed_at']),
      cancelledAt: parseDate(json['cancelled_at']),
      canAccept: json['can_accept'] as bool? ?? false,
      canReject: json['can_reject'] as bool? ?? false,
      canCancel: json['can_cancel'] as bool? ?? false,
    );
  }
}