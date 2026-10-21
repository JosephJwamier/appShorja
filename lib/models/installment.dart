/// التقسيط كما يراه التطبيق.
///
/// لا شيء هنا يعرف «كي كارد» بالاسم: الشروط والنِسَب والتسمية تأتي من
/// الخادم، فتغيير المموّل أو إعادة التفاوض على نسبة لا يحتاج إصدار تطبيق
/// جديد — تماماً كما في [PaymentMethod] للبوابات.
class InstallmentOptions {
  final String provider;
  final String labelAr;
  final int months;
  final double customerFeePercent;
  final double minAmount;
  final double maxAmount;

  const InstallmentOptions({
    required this.provider,
    required this.labelAr,
    required this.months,
    required this.customerFeePercent,
    required this.minAmount,
    required this.maxAmount,
  });

  /// هل يصلح هذا المبلغ للتقسيط؟ يُقرأ قبل عرض الزرّ، فلا يُفتح للمشتري
  /// باب يُغلق في وجهه بعد أن يُدخل رقم بطاقته.
  bool allows(double amount) {
    if (minAmount > 0 && amount < minAmount) return false;
    if (maxAmount > 0 && amount > maxAmount) return false;
    return true;
  }

  /// تقدير القسط الشهري قبل أي بطاقة — للعرض فقط؛ الرقم المُلزِم يأتي من
  /// الخادم بعد الفحص (قد يُعيد المموّل جدولاً خاصاً بالبطاقة).
  double monthlyFor(double amount) {
    if (months <= 0) return amount;
    return (amount + amount * customerFeePercent / 100) / months;
  }

  factory InstallmentOptions.fromJson(Map<String, dynamic> json) {
    return InstallmentOptions(
      provider: json['provider'] as String? ?? '',
      labelAr: json['label_ar'] as String? ?? 'تقسيط',
      months: json['months'] as int? ?? 0,
      customerFeePercent: _toDouble(json['customer_fee_percent']),
      minAmount: _toDouble(json['min_amount']),
      maxAmount: _toDouble(json['max_amount']),
    );
  }
}

/// خطة تقسيط: عرضٌ بعد الفحص (`quoted`)، أو خطة قائمة بعد التأكيد.
class InstallmentPlan {
  final String reference;
  final String state;
  final String stateLabel;

  /// المبلغ المموَّل (ثمن المنتج + أجرة التوصيل) — ما كان سيُدفع نقداً.
  final double principal;
  final int months;
  final double monthlyAmount;

  /// ما يدفعه المشتري إجمالاً للمموّل، ونسبته التي تُضاف فوق السعر.
  final double totalPayable;
  final double customerFeeAmount;
  final double customerFeePercent;

  final double collectedAmount;
  final int collectedCount;
  final String cardLast4;
  final String cardHolderName;

  const InstallmentPlan({
    required this.reference,
    required this.state,
    this.stateLabel = '',
    required this.principal,
    required this.months,
    required this.monthlyAmount,
    required this.totalPayable,
    this.customerFeeAmount = 0,
    this.customerFeePercent = 0,
    this.collectedAmount = 0,
    this.collectedCount = 0,
    this.cardLast4 = '',
    this.cardHolderName = '',
  });

  bool get isActive => state == 'active' || state == 'settled';
  int get remainingCount =>
      (months - collectedCount) < 0 ? 0 : months - collectedCount;

  factory InstallmentPlan.fromJson(Map<String, dynamic> json) {
    return InstallmentPlan(
      reference: json['reference'] as String? ?? '',
      state: json['state'] as String? ?? 'quoted',
      stateLabel: json['state_label'] as String? ?? '',
      principal: _toDouble(json['principal']),
      months: json['months'] as int? ?? 0,
      monthlyAmount: _toDouble(json['monthly_amount']),
      totalPayable: _toDouble(json['total_payable']),
      customerFeeAmount: _toDouble(json['customer_fee_amount']),
      customerFeePercent: _toDouble(json['customer_fee_percent']),
      collectedAmount: _toDouble(json['collected_amount']),
      collectedCount: json['collected_count'] as int? ?? 0,
      cardLast4: json['card_last4'] as String? ?? '',
      cardHolderName: json['card_holder_name'] as String? ?? '',
    );
  }
}

/// ملخّص التمويل المرفق بكل حجز في قائمة الحجوزات — ما تحتاجه بطاقة الطلب
/// لتقول «مقسّطة» وتعرض القسط، بلا نداء إضافي.
class ReservationInstallment {
  final String reference;
  final String state;
  final int months;
  final double monthlyAmount;
  final double totalPayable;
  final String cardLast4;
  final int collectedCount;

  const ReservationInstallment({
    required this.reference,
    required this.state,
    required this.months,
    required this.monthlyAmount,
    required this.totalPayable,
    this.cardLast4 = '',
    this.collectedCount = 0,
  });

  int get remainingCount =>
      (months - collectedCount) < 0 ? 0 : months - collectedCount;

  factory ReservationInstallment.fromJson(Map<String, dynamic> json) {
    return ReservationInstallment(
      reference: json['reference'] as String? ?? '',
      state: json['state'] as String? ?? '',
      months: json['months'] as int? ?? 0,
      monthlyAmount: _toDouble(json['monthly_amount']),
      totalPayable: _toDouble(json['total_payable']),
      cardLast4: json['card_last4'] as String? ?? '',
      collectedCount: json['collected_count'] as int? ?? 0,
    );
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
