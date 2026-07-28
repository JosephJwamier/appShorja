import 'package:firebase_analytics/firebase_analytics.dart';

/// Single shared FirebaseAnalytics instance + funnel event helpers.
///
/// Centralizing the event names/parameters here (rather than scattering
/// hand-typed `logEvent()` calls across services and screens) keeps the
/// funnel taxonomy consistent — without this, there is no way to answer
/// "where do buyers actually drop off: browsing, reservation, payment, or
/// delivery?" Standard Firebase/GA4 ecommerce event names (`view_item`,
/// `begin_checkout`, `purchase`) are used where they map cleanly, since
/// those plug straight into Firebase's built-in funnel reports.
class AppAnalytics {
  AppAnalytics._();
  static final FirebaseAnalytics instance = FirebaseAnalytics.instance;

  static Future<void> viewItem({
    required String itemId,
    required String itemName,
    required String contentType, // 'listing' | 'auction'
  }) =>
      instance.logEvent(
        name: 'view_item',
        parameters: {
          'item_id': itemId,
          'item_name': itemName,
          'content_type': contentType,
        },
      );

  /// Logged when the reservation sheet (quantity + delivery) opens — the
  /// first real commitment step after browsing.
  static Future<void> beginCheckout({
    required String itemId,
    required double value,
  }) =>
      instance.logEvent(
        name: 'begin_checkout',
        parameters: {'item_id': itemId, 'value': value, 'currency': 'IQD'},
      );

  /// Logged once a reservation exists ('pending') — before any money has
  /// actually moved (see [purchase] for that).
  static Future<void> reservationCreated({
    required String reservationId,
    required String itemId,
    required double value,
  }) =>
      instance.logEvent(
        name: 'reservation_created',
        parameters: {
          'reservation_id': reservationId,
          'item_id': itemId,
          'value': value,
          'currency': 'IQD',
        },
      );

  /// Logged when the buyer actually pays (deposit or full) — the money
  /// moment, distinct from [reservationCreated].
  static Future<void> purchase({
    required String reservationId,
    required double value,
    required String paymentType, // 'deposit' | 'full'
  }) =>
      instance.logEvent(
        name: 'purchase',
        parameters: {
          'transaction_id': reservationId,
          'value': value,
          'currency': 'IQD',
          'payment_type': paymentType,
        },
      );

  static Future<void> deliveryConfirmed({required String deliveryOrderId}) =>
      instance.logEvent(
        name: 'delivery_confirmed',
        parameters: {'delivery_order_id': deliveryOrderId},
      );

  static Future<void> login({required String method}) =>
      instance.logEvent(name: 'login', parameters: {'method': method});

  static Future<void> signUp({required String method}) =>
      instance.logEvent(name: 'sign_up', parameters: {'method': method});
}
