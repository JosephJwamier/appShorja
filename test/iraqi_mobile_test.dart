// قاعدة الرقم العراقي مكرّرة عمداً في طرفين: الخادم
// (core/phone_utils.py) والتطبيق (lib/utils/formatters.dart). التكرار
// يشتري كشفاً فورياً للخطأ قبل الرحلة إلى الخادم، وثمنه أن ينحرف الطرفان.
// هذه الحالات هي نفسها الموجودة في core/tests/test_phone_utils.py — فإن
// تغيّرت القاعدة هناك ولم تتغيّر هنا، يسقط هذا الملف.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/utils/formatters.dart';

void main() {
  group('isIraqiMobile يقبل', () {
    for (final typed in [
      '07701234567',
      '7701234567',
      '+9647701234567',
      '9647701234567',
      '009647701234567',
      '0770 123 4567',
      '0770-123-4567',
    ]) {
      test('«$typed»', () => expect(isIraqiMobile(typed), isTrue));
    }

    for (final prefix in ['75', '77', '78', '79']) {
      test('البادئة $prefix', () {
        expect(isIraqiMobile('0${prefix}01234567'), isTrue);
      });
    }
  });

  group('isIraqiMobile يرفض', () {
    for (final typed in [
      '',
      '0770123456',    // خانة ناقصة
      '077012345678',  // خانة زائدة
      '07401234567',   // بادئة غير مخصّصة
      '017184512',     // أرضي: لا يستقبل رسالة
      '+15551234567',  // رقم حقيقي، دولة أخرى
      'abcdefghij',
    ]) {
      test('«$typed»', () => expect(isIraqiMobile(typed), isFalse));
    }
  });

  test('توافق toE164 مع الصيغة المعيارية في الخادم', () {
    expect(toE164('07701234567'), '+9647701234567');
    expect(toE164('0770 123 4567'), '+9647701234567');
  });
}
