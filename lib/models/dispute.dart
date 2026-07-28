import 'product.dart';
import 'user.dart';

class Dispute {
  final int id;
  final Product item;
  final int? reservationId;
  final User complainant;
  final User defendant;
  final String title;
  final String description;
  final String reason;
  final String status;
  final String adminNotes;
  final String resolution;
  final String resolutionAction;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final bool canResolve;

  Dispute({
    required this.id,
    required this.item,
    this.reservationId,
    required this.complainant,
    required this.defendant,
    required this.title,
    required this.description,
    required this.reason,
    required this.status,
    required this.adminNotes,
    required this.resolution,
    required this.resolutionAction,
    required this.createdAt,
    this.resolvedAt,
    required this.canResolve,
  });

  bool isPartOf(int userId) => complainant.id == userId || defendant.id == userId;
  bool isComplainant(int userId) => complainant.id == userId;

  factory Dispute.fromJson(Map<String, dynamic> json) {
    final reservation = json['reservation'] as Map<String, dynamic>?;
    return Dispute(
      id: json['id'] as int,
      item: Product.fromJson(json['item'] as Map<String, dynamic>),
      reservationId: reservation?['id'] as int?,
      complainant: User.fromJson(json['complainant'] as Map<String, dynamic>),
      defendant: User.fromJson(json['defendant'] as Map<String, dynamic>),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      adminNotes: json['admin_notes'] as String? ?? '',
      resolution: json['resolution'] as String? ?? '',
      resolutionAction: json['resolution_action'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      canResolve: json['can_resolve'] as bool? ?? false,
    );
  }
}

/// Common dispute reasons offered as quick-pick chips in the filing form.
/// Value is what's sent to the backend; label is what the user sees.
const disputeReasons = <({String value, String label})>[
  (value: 'item_not_received', label: 'لم يصل المنتج'),
  (value: 'item_mismatch', label: 'المنتج غير مطابق للوصف'),
  (value: 'item_damaged', label: 'المنتج تالف'),
  (value: 'seller_unresponsive', label: 'البائع لا يستجيب'),
  (value: 'payment_issue', label: 'مشكلة في الدفع'),
  (value: 'other', label: 'أخرى'),
];

String disputeReasonLabel(String value) {
  for (final r in disputeReasons) {
    if (r.value == value) return r.label;
  }
  return value;
}

String disputeStatusLabel(String status) {
  switch (status) {
    case 'open':
      return 'مفتوح';
    case 'investigating':
      return 'قيد المراجعة';
    case 'resolved':
      return 'تمّ الحل';
    case 'closed':
      return 'مُغلق';
    default:
      return status;
  }
}

String disputeResolutionLabel(String action) {
  switch (action) {
    case 'refund_buyer':
      return 'تمّ استرجاع المبلغ للزبون';
    case 'pay_seller':
      return 'تمّ الدفع للبائع';
    case 'partial_refund':
      return 'استرجاع جزئي';
    case 'no_action':
      return 'لا يوجد إجراء';
    default:
      return action;
  }
}
