/// A single delivery leg handed off to the delivery company — either the
/// outbound trip (seller -> buyer) or a return trip (buyer -> seller, after
/// a refused delivery or a dispute resolved in the buyer's favour).
/// Mirrors core.serializers.DeliveryOrderSerializer on the backend.
class DeliveryOrder {
  final int id;
  final int reservationId;
  final int? batchId;
  final String direction; // 'outbound' | 'return'
  final String status; // assigned | picked_up | delivered | confirmed | refused | failed | cancelled

  final String fromName;
  final String fromPhone;
  final String fromAddress;
  final String? fromMapsUrl;

  final String toName;
  final String toPhone;
  final String toAddress;
  final String? toMapsUrl;

  final String itemSummary;
  final int quantity;
  final String specialNotes;
  final double cashToCollect;
  final bool cashCollected;
  final String failureReason;

  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? confirmedAt;
  final DateTime? refusedAt;
  final DateTime? cashCollectedAt;

  const DeliveryOrder({
    required this.id,
    required this.reservationId,
    this.batchId,
    required this.direction,
    required this.status,
    required this.fromName,
    required this.fromPhone,
    required this.fromAddress,
    this.fromMapsUrl,
    required this.toName,
    required this.toPhone,
    required this.toAddress,
    this.toMapsUrl,
    required this.itemSummary,
    required this.quantity,
    this.specialNotes = '',
    this.cashToCollect = 0,
    this.cashCollected = false,
    this.failureReason = '',
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.confirmedAt,
    this.refusedAt,
    this.cashCollectedAt,
  });

  bool get isOutbound => direction == 'outbound';

  /// True once the company has physically handed the item to the buyer and
  /// is waiting on the buyer to press "received" or "refuse" in the app.
  bool get awaitingReceiptDecision => isOutbound && status == 'delivered';

  /// True if this leg was bundled with others into one delivery trip — see
  /// ReservationViewSet.send_to_delivery_batch on the backend.
  bool get isMerged => batchId != null;

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static DateTime? _toDate(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    return DeliveryOrder(
      id: json['id'] as int,
      reservationId: json['reservation'] as int,
      batchId: json['batch'] as int?,
      direction: json['direction'] as String,
      status: json['status'] as String,
      fromName: json['from_name'] as String? ?? '',
      fromPhone: json['from_phone'] as String? ?? '',
      fromAddress: json['from_address'] as String? ?? '',
      fromMapsUrl: json['from_maps_url'] as String?,
      toName: json['to_name'] as String? ?? '',
      toPhone: json['to_phone'] as String? ?? '',
      toAddress: json['to_address'] as String? ?? '',
      toMapsUrl: json['to_maps_url'] as String?,
      itemSummary: json['item_summary'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 1,
      specialNotes: json['special_notes'] as String? ?? '',
      cashToCollect: _toDouble(json['cash_to_collect']),
      cashCollected: json['cash_collected'] as bool? ?? false,
      failureReason: json['failure_reason'] as String? ?? '',
      assignedAt: _toDate(json['assigned_at']),
      pickedUpAt: _toDate(json['picked_up_at']),
      deliveredAt: _toDate(json['delivered_at']),
      confirmedAt: _toDate(json['confirmed_at']),
      refusedAt: _toDate(json['refused_at']),
      cashCollectedAt: _toDate(json['cash_collected_at']),
    );
  }
}
