// استنتاج المحافظة من دبّوس الخريطة. الغرض إسقاط حقل من نموذج إضافة
// الموقع، لا رسم حدود إدارية — فما يُختبر هو أن المدن الكبرى تصيب،
// وأن النتيجة دائماً محافظة صالحة مهما كانت النقطة.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:marketplace_app/features/location/models/iraq_governorate.dart';

void main() {
  group('يصيب مراكز المدن', () {
    const cases = {
      'بغداد': LatLng(33.3152, 44.3661),
      'البصرة': LatLng(30.5085, 47.7804),
      'أربيل': LatLng(36.1911, 44.0093),
      'النجف': LatLng(31.9960, 44.3095),
      'دهوك': LatLng(36.8617, 42.9951),
    };
    cases.forEach((expected, point) {
      test(expected, () {
        expect(nearestGovernorate(point).name, expected);
      });
    });
  });

  test('نقطة داخل بغداد لا في مركزها تبقى بغداد', () {
    // الكاظمية، شمال غرب المركز بنحو 8 كم.
    expect(nearestGovernorate(const LatLng(33.3800, 44.3400)).name, 'بغداد');
  });

  test('نقطة خارج العراق تعطي محافظة لا خطأ', () {
    // الكويت. النتيجة اقتراح يصحّحه المستخدم، والمهم ألا تنهار الشاشة.
    final result = nearestGovernorate(const LatLng(29.3759, 47.9774));
    expect(iraqGovernorates.map((g) => g.name), contains(result.name));
  });

  test('كل محافظة تستطيع أن تكون النتيجة لمركزها', () {
    // يحرس من خطأ شائع: حلقة تُرجع الأولى دائماً لأن الشرط مقلوب.
    for (final governorate in iraqGovernorates) {
      expect(nearestGovernorate(governorate.center).name, governorate.name);
    }
  });
}
