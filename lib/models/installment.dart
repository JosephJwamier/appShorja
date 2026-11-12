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

  /// ما تخصمه كي كارد من المبلغ المكتوب لها، ورسم المنصة من ثمن الطلب —
  /// يحملهما الزبون أيضاً.
  final double merchantFeePercent;
  final double platformFeePercent;
  final double minAmount;
  final double maxAmount;

  /// المضاعف الذي يُدوَّر إليه المبلغ المكتوب في كي كارد (500 افتراضاً).
  /// يأتي من الخادم ولا يُكتب هنا، فتغييره لا يحتاج إصدار تطبيق.
  final double roundingStep;

  /// 'manual': المشتري يرسل رقم حسابه والإدارة تتصل به لإكمال التفعيل.
  /// 'api': فحص البطاقة والجدول ثم تأكيد فوري.
  final String mode;

  const InstallmentOptions({
    required this.provider,
    required this.labelAr,
    required this.months,
    required this.customerFeePercent,
    this.merchantFeePercent = 0,
    this.platformFeePercent = 0,
    this.roundingStep = 1,
    required this.minAmount,
    required this.maxAmount,
    this.mode = 'manual',
  });

  bool get isManual => mode != 'api';

  /// هل يصلح هذا المبلغ للتقسيط؟ يُقرأ قبل عرض الزرّ، فلا يُفتح للمشتري
  /// باب يُغلق في وجهه بعد أن يُدخل رقم بطاقته.
  bool allows(double amount) {
    if (minAmount > 0 && amount < minAmount) return false;
    if (maxAmount > 0 && amount > maxAmount) return false;
    return true;
  }

  /// ما يُكتب في كي كارد لطلب بهذا المبلغ: يُرفع حتى يبقى للمنصة بعد خصم
  /// نسبة كي كارد من التاجر ثمنُ الطلب ورسمُ المنصة. نفس معادلة الخادم
  /// (services/installments/service.pricing).
  double qiAmountFor(double amount) {
    final keep = 1 - merchantFeePercent / 100;
    if (keep <= 0) return amount;
    final raw = amount * (1 + platformFeePercent / 100) / keep;
    if (roundingStep <= 1) return raw.ceilToDouble();
    // لأعلى مضاعف لـ roundingStep، كما يفعل الخادم بالضبط: تقديرٌ يخالف
    // الرقم المُلزِم بثلاثمئة دينار يبدو خطأً للمشتري ولو كان تدويراً.
    return (raw / roundingStep).ceilToDouble() * roundingStep;
  }

  /// كل ما يدفعه الزبون: المبلغ المكتوب في كي كارد ونسبتها فوقه.
  double totalFor(double amount) {
    final qi = qiAmountFor(amount);
    return qi + qi * customerFeePercent / 100;
  }

  /// تقدير القسط الشهري قبل أي طلب — للعرض فقط؛ الرقم المُلزِم يأتي من
  /// الخادم مع الطلب.
  double monthlyFor(double amount) {
    if (months <= 0) return totalFor(amount);
    return (totalFor(amount) / months).ceilToDouble();
  }

  factory InstallmentOptions.fromJson(Map<String, dynamic> json) {
    return InstallmentOptions(
      provider: json['provider'] as String? ?? '',
      labelAr: json['label_ar'] as String? ?? 'تقسيط',
      months: json['months'] as int? ?? 0,
      customerFeePercent: _toDouble(json['customer_fee_percent']),
      merchantFeePercent: _toDouble(json['merchant_fee_percent']),
      platformFeePercent: _toDouble(json['platform_fee_percent']),
      // 1 = بلا تدوير، وهي حال نسخة خادم قديمة لا تُرسل الحقل.
      roundingStep: _toDouble(json['rounding_step']) <= 0
          ? 1
          : _toDouble(json['rounding_step']),
      minAmount: _toDouble(json['min_amount']),
      maxAmount: _toDouble(json['max_amount']),
      mode: json['mode'] as String? ?? 'manual',
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

  /// كل ما فوق ثمن الطلب: نسبتا كي كارد ورسم المنصة، بنداً واحداً.
  final double feesAmount;
  final double customerFeePercent;

  final double collectedAmount;
  final int collectedCount;
  final String cardLast4;
  final String cardHolderName;

  /// سبب الرفض حين ترفض الإدارة طلب التقسيط.
  final String failureReason;

  const InstallmentPlan({
    required this.reference,
    required this.state,
    this.stateLabel = '',
    required this.principal,
    required this.months,
    required this.monthlyAmount,
    required this.totalPayable,
    this.customerFeeAmount = 0,
    this.feesAmount = 0,
    this.customerFeePercent = 0,
    this.collectedAmount = 0,
    this.collectedCount = 0,
    this.cardLast4 = '',
    this.cardHolderName = '',
    this.failureReason = '',
  });

  bool get isActive => state == 'active' || state == 'settled';
  bool get isRequested => state == 'requested';
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
      feesAmount: json['fees_amount'] != null
          ? _toDouble(json['fees_amount'])
          : _toDouble(json['total_payable']) - _toDouble(json['principal']),
      customerFeePercent: _toDouble(json['customer_fee_percent']),
      collectedAmount: _toDouble(json['collected_amount']),
      collectedCount: json['collected_count'] as int? ?? 0,
      cardLast4: json['card_last4'] as String? ?? '',
      cardHolderName: json['card_holder_name'] as String? ?? '',
      failureReason: json['failure_reason'] as String? ?? '',
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

  /// أرسل المشتري رقم حسابه والإدارة لم تقرّر بعد — «سيتم الاتصال بك».
  bool get isRequested => state == 'requested';

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
