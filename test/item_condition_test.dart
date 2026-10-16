// أسماء الحالات: مصدر واحد بعد أن كانت مكرّرة في خمسة مواضع.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/utils/item_condition.dart';

void main() {
  test('الحالات الأربع لها أسماء عربية', () {
    expect(conditionLabel('new'), 'جديد');
    expect(conditionLabel('like_new'), 'شبه جديد');
    expect(conditionLabel('used'), 'مستعمل');
    expect(conditionLabel('unknown'), 'غير معلوم');
  });

  test('حالة متقاعدة من صفّ قديم لا تظهر بالإنجليزية', () {
    // 'good' و'fair' و'poor' أُسقطت من الخادم، وقد تبقى في بيانات قديمة.
    for (final retired in ['good', 'fair', 'poor']) {
      expect(conditionLabel(retired), 'غير معلوم');
    }
  });

  test('القيمة الفارغة أو المفقودة لا تنهار', () {
    expect(conditionLabel(null), 'غير معلوم');
    expect(conditionLabel(''), 'غير معلوم');
  });

  test('لا يُعاد الرمز الخام أبداً', () {
    for (final code in ['new', 'zzz', null, '', 'LIKE_NEW']) {
      expect(kConditionLabels.values, contains(conditionLabel(code)));
    }
  });
}
