// الجلسة محفوظة في مخزنين: الرمزان في التخزين الآمن، والمستخدم في
// SharedPreferences. ونسيان أحدهما يُنتج «جلسة نصفها محفوظ» — وهو ما
// حدث فعلاً: register كان يحفظ الرمزين ولا يحفظ المستخدم، فيُعاد فتح
// التطبيق بمستخدم مسجَّل بلا اسم ولا صورة.
//
// ما يحرسه هذا الملف هو الدورة نفسها: ما يُكتب إلى التخزين يجب أن يعود
// كما هو، فيبقى العطل محصوراً في «من نسي أن يكتب» لا في «الكتابة نفسها».
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/user.dart';

final _user = User(
  id: 7,
  username: 'u9647701234567',
  firstName: 'عبد',
  lastName: 'الرحمن',
  email: 'ali@example.com',
  phone: '+9647701234567',
  emailVerified: true,
  phoneVerified: true,
  trustScore: 4.5,
  bio: 'تاجر هواتف',
);

User roundTrip(User user) =>
    User.fromJson(jsonDecode(jsonEncode(user.toJson())) as Map<String, dynamic>);

void main() {
  test('الاسم ينجو من الحفظ والاسترجاع', () {
    final restored = roundTrip(_user);
    expect(restored.firstName, 'عبد');
    expect(restored.lastName, 'الرحمن');
    expect(restored.displayName, 'عبد الرحمن');
  });

  test('الهوية والرقم ينجوان', () {
    final restored = roundTrip(_user);
    expect(restored.id, 7);
    expect(restored.username, 'u9647701234567');
    expect(restored.phone, '+9647701234567');
  });

  test('حالات التوثيق تنجو', () {
    final restored = roundTrip(_user);
    expect(restored.emailVerified, isTrue);
    expect(restored.phoneVerified, isTrue);
  });

  test('حساب بلا اسم يعرض اسم المستخدم لا فراغاً', () {
    // الأسماء صارت إجبارية عند التسجيل، لكن حسابات أقدم وحساب المدير
    // (createsuperuser) بلا أسماء — ويجب أن يظهر لها شيء.
    final nameless = User(id: 1, username: 'higel', email: '', phone: '');
    expect(roundTrip(nameless).displayName, 'higel');
  });

  test('كائن فارغ تماماً لا ينهار', () {
    // لو وصلت حمولة ناقصة من الخادم، تُقرأ بقيم افتراضية بدل استثناء
    // يمنع الإقلاع كله.
    final empty = User.fromJson(const {});
    expect(empty.id, 0);
    expect(empty.displayName, '');
  });
}
