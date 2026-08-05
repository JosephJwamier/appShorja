import 'dart:convert';
import '../models/delivery_order.dart';
import 'analytics_service.dart';
import 'api_client.dart';

/// Calls the delivery hand-off endpoints — the platform does not manage the
/// delivery company's drivers, it only hands a leg off and later reacts to
/// the buyer confirming or refusing receipt. See core.views.DeliveryOrderViewSet
/// and ReservationViewSet.send_to_delivery on the backend.
class DeliveryService {
  final _client = ApiClient.instance;

  // accessToken is kept for call-site compatibility — ApiClient tracks the
  // live token itself (and silently refreshes it on a 401).

  /// Seller sends a paid reservation off to the delivery company, instead of
  /// cancelling it.
  Future<DeliveryOrder> sendToDelivery({
    required String accessToken,
    required int reservationId,
  }) async {
    final response =
        await _client.post('/reservations/$reservationId/send-to-delivery/');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      return DeliveryOrder.fromJson(data['data'] as Map<String, dynamic>);
    }
    throw Exception(data['message'] ?? 'فشل إسناد الطلب لشركة التوصيل');
  }

  /// Seller bundles several paid reservations for the same buyer/address
  /// into as few delivery trips as fit the company's size cap — one
  /// delivery fee per trip instead of one per reservation. The buyer is
  /// refunded (or has their COD reduced) for the reservations that end up
  /// riding along for free — see core.delivery_utils.combine_deliveries.
  Future<({int trips, double refundedAmount, List<DeliveryOrder> orders})>
      sendToDeliveryBatch({
    required String accessToken,
    required List<int> reservationIds,
  }) async {
    final response = await _client.post(
      '/reservations/send-to-delivery-batch/',
      body: {'reservation_ids': reservationIds},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      final orders = (data['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((e) => DeliveryOrder.fromJson(e))
          .toList();
      return (
        trips: data['trips'] as int,
        refundedAmount:
            double.tryParse(data['refunded_amount'].toString()) ?? 0,
        orders: orders,
      );
    }
    throw Exception(data['message'] ?? 'فشل دمج التوصيل');
  }

  /// Buyer presses "received" once the item has physically arrived. This
  /// only confirms physical receipt — it does NOT release the held payment.
  /// The payment is released automatically once the item's warranty period
  /// passes with no dispute, or earlier if the buyer explicitly approves via
  /// ReservationService.approveAndReleasePayment. Returns the backend's
  /// message, which already reflects the item's actual warranty length.
  Future<String> confirmReceipt({
    required String accessToken,
    required int deliveryOrderId,
  }) async {
    final response =
        await _client.post('/delivery-orders/$deliveryOrderId/confirm-receipt/');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(data['message'] ?? 'فشل تأكيد الاستلام');
    }
    AppAnalytics.deliveryConfirmed(deliveryOrderId: deliveryOrderId.toString());
    return data['message'] as String? ?? 'تم تأكيد الاستلام';
  }

  /// Buyer refuses the item at the door. With a `reason`, this opens a
  /// support-reviewed dispute (full refund is the admin's call); with no
  /// reason it's a plain refusal — the deposit (+ delivery fee if paid in
  /// full) is forfeited once the company confirms it collected the item
  /// back, and only the rest is refunded. Returns the backend's message,
  /// which already reflects which of the two this was.
  Future<String> refuseReceipt({
    required String accessToken,
    required int deliveryOrderId,
    String reason = '',
  }) async {
    final response = await _client.post(
      '/delivery-orders/$deliveryOrderId/refuse-receipt/',
      body: {'reason': reason},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(data['message'] ?? 'فشل رفض الاستلام');
    }
    return data['message'] as String? ?? 'تم رفض الاستلام';
  }
}
