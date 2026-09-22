import 'dart:convert';
import '../models/reservation.dart';
import 'analytics_service.dart';
import 'api_client.dart';

class ReservationService {
  final _client = ApiClient.instance;

  // accessToken is kept for call-site compatibility — ApiClient tracks the
  // live token itself (and silently refreshes it on a 401), so it's no
  // longer read directly here.
  Future<List<Reservation>> fetchReservations({
    required String accessToken,
  }) async {
    final response = await _client.get('/reservations/');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return results
          .map((r) => Reservation.fromJson(r as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('فشل جلب الحجوزات');
    }
  }

  Future<void> cancelReservation({
    required String accessToken,
    required int reservationId,
  }) async {
    final response = await _client.post('/reservations/$reservationId/cancel/');

    if (response.statusCode != 200 && response.statusCode != 204) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'فشل إلغاء الحجز');
    }
  }

  /// [paymentType] is `'full'` (pay the entire price now) or `'deposit'`
  /// (pay only the deposit now — the remainder is collected in cash at
  /// delivery, outside the app). [value] (the amount actually charged) is
  /// only used for funnel logging — pass it when known so the `purchase`
  /// event carries a real amount instead of being skipped.
  Future<void> completeReservation({
    required String accessToken,
    required int reservationId,
    String paymentType = 'full',
    int? deliveryLocationId,
    double? value,
  }) async {
    final response = await _client.post(
      '/reservations/$reservationId/complete/',
      body: {
        'payment_type': paymentType,
        if (deliveryLocationId != null)
          'delivery_location_id': deliveryLocationId.toString(),
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'فشل إكمال الحجز');
    }

    if (value != null) {
      AppAnalytics.purchase(
        reservationId: reservationId.toString(),
        value: value,
        paymentType: paymentType,
      );
    }
  }

  /// Buyer changes the delivery address on their own reservation. Only
  /// accepted before the seller hands it off to the delivery company (see
  /// Reservation.deliveryOrder) — the backend locks it after that.
  Future<void> updateDeliveryLocation({
    required String accessToken,
    required int reservationId,
    required int deliveryLocationId,
  }) async {
    final response = await _client.post(
      '/reservations/$reservationId/update-delivery-location/',
      body: {'delivery_location_id': deliveryLocationId.toString()},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'فشل تعديل عنوان التوصيل');
    }
  }

  /// Buyer confirms receipt of the item, releasing the held payment to the
  /// seller immediately (instead of waiting for the automatic release once
  /// the item's warranty period elapses).
  Future<void> approveAndReleasePayment({
    required String accessToken,
    required int reservationId,
  }) async {
    final response = await _client
        .post('/reservations/$reservationId/approve_and_release_payment/');

    if (response.statusCode != 200 && response.statusCode != 204) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'فشل تأكيد الاستلام');
    }
  }

  /// Seller asks the buyer to confirm receipt and release the held payment
  /// (sends the buyer a push/in-app notification with a confirm-receipt action).
  Future<void> requestPaymentRelease({
    required String accessToken,
    required int reservationId,
  }) async {
    final response = await _client
        .post('/reservations/$reservationId/request_payment_release/');

    if (response.statusCode != 200 && response.statusCode != 204) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'فشل إرسال طلب تحرير الدفعة');
    }
  }

  Future<Map<String, dynamic>> createReservation({
    required String accessToken,
    required int itemId,
    required int quantity,
    /// Which combination (colour/size) is being bought. Required by the
    /// server when the item has options; ignored for plain items.
    int? variantId,
    int? couponCollectionId,
    int? deliveryLocationId,
    int? offerMessageId,
  }) async {
    final response = await _client.post(
      '/reservations/create_reservation/',
      body: {
        'item_id': itemId,
        'variant_id': ?variantId,
        'quantity': quantity,
        'delivery_location_id': ?deliveryLocationId,
        'coupon_collection_id': ?couponCollectionId,
        'offer_message_id': ?offerMessageId,
      },
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      final reservation = data['data'] as Map<String, dynamic>;
      final totalPrice = double.tryParse(reservation['total_price']?.toString() ?? '');
      if (reservation['id'] != null && totalPrice != null) {
        AppAnalytics.reservationCreated(
          reservationId: reservation['id'].toString(),
          itemId: itemId.toString(),
          value: totalPrice,
        );
      }
      return reservation;
    } else {
      throw Exception(data['message'] ?? 'فشل إنشاء الحجز');
    }
  }
}

/// What delivery will cost for one item to one saved address — the same
/// rule the server applies when charging, so the sheet never shows a
/// number the reservation then contradicts.
class DeliveryQuote {
  final double fee;
  final String? company;
  final String? fromGovernorate;
  final String? toGovernorate;
  const DeliveryQuote({required this.fee, this.company, this.fromGovernorate, this.toGovernorate});

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) => DeliveryQuote(
        fee: double.tryParse(json['fee']?.toString() ?? '') ?? 0,
        company: json['company']?.toString(),
        fromGovernorate: json['from_governorate']?.toString(),
        toGovernorate: json['to_governorate']?.toString(),
      );
}

extension DeliveryQuoteApi on ReservationService {
  Future<DeliveryQuote> fetchDeliveryQuote({
    required int itemId,
    required int locationId,
  }) async {
    final response = await _client.get(
      '/reservations/delivery-quote/?item_id=$itemId&location_id=$locationId',
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return DeliveryQuote.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw Exception('تعذّر حساب أجرة التوصيل');
  }
}
