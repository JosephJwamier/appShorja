// المقياس يعد المستخدم بشيء: أن ما يقبله هنا يقبله الخادم. وإخلافه مرّة
// واحدة يُفقده قيمته كلّها — فالمستخدم يرى «قويّة» ثم يُردّ، فلا ينظر إليه
// بعدها.
//
// فما يُحرَس هنا هو المطابقة لـ`AUTH_PASSWORD_VALIDATORS` في الخادم:
// ثمانية أحرف، وليست أرقاماً فقط، وليست شائعة، ولا تشبه بيانات صاحبها.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/utils/password_strength.dart';

void main() {
  group('ما يرفضه الخادم يُرفض هنا', () {
    test('أقصر من ثمانية', () {
      final v = ratePassword('Ab3!x');
      expect(v.meetsMinimum, isFalse);
      expect(v.strength, PasswordStrength.weak);
      expect(v.hint, contains('3'), reason: 'يقول كم ينقص لا «قصيرة»');
    });

    test('أرقام فقط — ولو كانت طويلة', () {
      // NumericPasswordValidator: الطول لا يُنقذ رقماً.
      final v = ratePassword('07701234567');
      expect(v.meetsMinimum, isFalse);
      expect(v.hint, contains('أرقام'));
    });

    test('كلمة شائعة', () {
      expect(ratePassword('password123').meetsMinimum, isFalse);
      expect(ratePassword('PASSWORD123').meetsMinimum, isFalse,
          reason: 'المقارنة لا تبالي بحالة الأحرف');
    });

    test('مبنيّة على الاسم', () {
      final v = ratePassword('kareem2026', personal: ['Kareem', 'Jwamier']);
      expect(v.meetsMinimum, isFalse);
      expect(v.hint, contains('اسمك'));
    });

    test('مبنيّة على البريد', () {
      expect(
          ratePassword('josephx99', personal: ['joseph@example.com'])
              .meetsMinimum,
          isFalse);
    });

    test('مبنيّة على أواخر الهاتف', () {
      // من يبني كلمة مرور على رقمه يأخذ آخره غالباً لا أوّله.
      final v = ratePassword('abc1234567x', personal: ['07701234567']);
      expect(v.meetsMinimum, isFalse);
    });
  });

  group('ما لا يُرفض بلا سبب', () {
    test('قطعة شخصية قصيرة لا تكفي للرفض', () {
      // «علي» ثلاثة أحرف، وتقع داخل كلمات كثيرة بلا قصد.
      expect(ratePassword('Calibrate88!', personal: ['علي', 'Ali']).meetsMinimum,
          isTrue);
    });

    test('بيانات شخصية فارغة لا تُسقط شيئاً', () {
      expect(ratePassword('Tajir!2026x', personal: ['', '  ', '']).meetsMinimum,
          isTrue);
    });
  });

  group('الدرجات فوق الحدّ الأدنى', () {
    test('الفارغة بلا درجة ولا شريط', () {
      expect(ratePassword('').strength, PasswordStrength.none);
    });

    test('ثمانية أحرف بحروف فقط: مقبولة', () {
      final v = ratePassword('abcdefgh');
      expect(v.meetsMinimum, isTrue);
      expect(v.strength, PasswordStrength.fair);
      expect(v.hint, isNotNull, reason: 'تمرّ، والتلميح اقتراح لا شرط');
    });

    test('حروف وأرقام وطول: جيّدة', () {
      expect(ratePassword('tajirshorja12').strength, PasswordStrength.good);
    });

    test('طويلة ومختلطة برموز: قويّة', () {
      expect(ratePassword('Tajir!Shorja#2026').strength,
          PasswordStrength.strong);
    });

    test('العربية تُحسب حروفاً', () {
      // لوحة المفاتيح العربية هي الافتراض عند تجّارنا.
      final v = ratePassword('بغدادالشورجة123');
      expect(v.meetsMinimum, isTrue);
      expect(v.strength, isNot(PasswordStrength.weak));
    });
  });

  group('حكم واحد للشريط وللنموذج', () {
    test('كل ما يمرّ له درجة فوق الضعيفة', () {
      for (final p in ['abcdefgh', 'tajirshorja12', 'Tajir!Shorja#2026']) {
        final v = ratePassword(p);
        expect(v.meetsMinimum, isTrue, reason: p);
        expect(v.strength, isNot(PasswordStrength.weak), reason: p);
      }
    });

    test('كل ما يُرفض ضعيف وله تلميح', () {
      for (final p in ['short', '12345678', 'password', 'qwerty123']) {
        final v = ratePassword(p);
        expect(v.meetsMinimum, isFalse, reason: p);
        expect(v.strength, PasswordStrength.weak, reason: p);
        expect(v.hint, isNotNull, reason: 'الرفض بلا سبب لا يُصلح شيئاً: $p');
      }
    });
  });
}
