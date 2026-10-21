// شروط التقسيط على جانب التطبيق.
//
// الحسابات هنا للعرض فقط — الرقم المُلزِم يأتي من الخادم بعد الفحص. لكنها
// الرقم الذي يراه المشتري قبل أن يُخرج بطاقته، فخطأ فيه يعني أنه قرّر على
// رقم غير الذي سيوقّع عليه. وأهمّها [InstallmentOptions.allows]: هي التي
// تُخفي الخيار على المبالغ التي يرفضها الخادم أصلاً، فلا يُفتح باب يُغلق
// في وجهه بعد أن يُدخل رقم بطاقته.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/installment.dart';

void main() {
  InstallmentOptions options({
    int months = 10,
    double fee = 10,
    double min = 250000,
    double max = 5000000,
  }) {
    return InstallmentOptions(
      provider: 'qicard',
      labelAr: 'تقسيط كي كارد',
      months: months,
      customerFeePercent: fee,
      minAmount: min,
      maxAmount: max,
    );
  }

  group('InstallmentOptions', () {
    test('القسط الشهري يحمل نسبة المموّل فوق السعر', () {
      // مليون + 10% = 1,100,000 على عشرة أشهر.
      expect(options().monthlyFor(1000000), 110000);
    });

    test('مبلغ تحت الحدّ الأدنى لا يُقسَّط', () {
      expect(options().allows(100000), isFalse);
    });

    test('مبلغ فوق السقف لا يُقسَّط', () {
      expect(options().allows(9000000), isFalse);
    });

    test('المبلغ على الحدّ نفسه مقبول', () {
      expect(options().allows(250000), isTrue);
      expect(options().allows(5000000), isTrue);
    });

    test('سقف صفر يعني لا سقف', () {
      expect(options(min: 0, max: 0).allows(900000000), isTrue);
    });

    test('أشهر صفر لا تقسم على صفر', () {
      expect(options(months: 0).monthlyFor(500000), 500000);
    });

    test('تُقرأ من جواب الخادم بأرقام نصّية', () {
      final parsed = InstallmentOptions.fromJson({
        'provider': 'qicard',
        'label_ar': 'تقسيط كي كارد',
        'months': 10,
        'customer_fee_percent': '10',
        'min_amount': '250000.00',
        'max_amount': '5000000.00',
      });
      expect(parsed.months, 10);
      expect(parsed.customerFeePercent, 10);
      expect(parsed.minAmount, 250000);
    });

    test('جواب ناقص لا يُسقِط التطبيق', () {
      final parsed = InstallmentOptions.fromJson({'provider': 'x'});
      expect(parsed.labelAr, 'تقسيط');
      expect(parsed.allows(1000000), isTrue);
    });
  });

  group('InstallmentPlan', () {
    test('تُقرأ الخطة من جواب التأكيد', () {
      final plan = InstallmentPlan.fromJson({
        'reference': 'INS-abc',
        'state': 'active',
        'principal': '1000000.00',
        'months': 10,
        'monthly_amount': '110000.00',
        'total_payable': '1100000.00',
        'customer_fee_amount': '100000.00',
        'collected_count': 3,
        'card_last4': '4321',
      });
      expect(plan.isActive, isTrue);
      expect(plan.monthlyAmount, 110000);
      expect(plan.remainingCount, 7);
      expect(plan.cardLast4, '4321');
    });

    test('العرض ليس خطة قائمة', () {
      final quote = InstallmentPlan.fromJson({
        'reference': 'INS-q',
        'state': 'quoted',
        'months': 10,
        'monthly_amount': '110000.00',
        'total_payable': '1100000.00',
        'principal': '1000000.00',
      });
      expect(quote.isActive, isFalse);
    });

    test('أقساط محصَّلة أكثر من المدّة لا تُنتج رقماً سالباً', () {
      final plan = InstallmentPlan.fromJson({
        'reference': 'INS-x',
        'state': 'settled',
        'months': 10,
        'collected_count': 12,
        'monthly_amount': '110000.00',
        'total_payable': '1100000.00',
        'principal': '1000000.00',
      });
      expect(plan.remainingCount, 0);
    });
  });

  group('ReservationInstallment', () {
    test('ملخّص الحجز يحمل ما تحتاجه بطاقة الطلب', () {
      final summary = ReservationInstallment.fromJson({
        'reference': 'INS-abc',
        'state': 'active',
        'months': 10,
        'monthly_amount': '110000.00',
        'total_payable': '1100000.00',
        'card_last4': '4321',
        'collected_count': 2,
      });
      expect(summary.monthlyAmount, 110000);
      expect(summary.remainingCount, 8);
    });
  });
}
