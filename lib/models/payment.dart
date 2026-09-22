/// A payment method the server is configured to process.
///
/// The label comes from the server, not from a switch statement here, so
/// adding a gateway needs no app release.
class PaymentMethod {
  final String provider;
  final String labelAr;
  final List<String> currencies;

  PaymentMethod({
    required this.provider,
    required this.labelAr,
    this.currencies = const ['IQD'],
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      provider: json['provider'] as String? ?? '',
      labelAr: json['label_ar'] as String? ?? json['provider'] as String? ?? '',
      currencies: (json['currencies'] as List<dynamic>? ?? const ['IQD'])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// One attempt to take money, mirroring the backend's PaymentIntent.
class PaymentIntent {
  final String reference;
  final String provider;
  final double amount;
  final String currency;

  /// pending / succeeded / failed / cancelled — the server's vocabulary, kept
  /// identical on both sides so neither has to translate.
  final String state;
  final String checkoutUrl;
  final String failureReason;

  PaymentIntent({
    required this.reference,
    required this.provider,
    required this.amount,
    required this.currency,
    required this.state,
    this.checkoutUrl = '',
    this.failureReason = '',
  });

  bool get isPending => state == 'pending';
  bool get isSucceeded => state == 'succeeded';
  bool get isFinal => state != 'pending';

  factory PaymentIntent.fromJson(Map<String, dynamic> json) {
    return PaymentIntent(
      reference: json['reference'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      amount: _toDouble(json['amount']),
      currency: json['currency'] as String? ?? 'IQD',
      state: json['state'] as String? ?? 'pending',
      checkoutUrl: json['checkout_url'] as String? ?? '',
      failureReason: json['failure_reason'] as String? ?? '',
    );
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
