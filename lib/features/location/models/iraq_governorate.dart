import 'package:latlong2/latlong.dart';

/// Fixed list of Iraq's 18 governorates (المحافظات), mirroring
/// `core/iraq_governorates.py` on the backend — `Location.state` is
/// constrained to these same names, so picking one here and sending it as
/// the `governorate` search param is guaranteed to match.
class IraqGovernorate {
  final String name;
  final double lat;
  final double lng;
  const IraqGovernorate(this.name, this.lat, this.lng);

  LatLng get center => LatLng(lat, lng);

  @override
  String toString() => name;
}

const List<IraqGovernorate> iraqGovernorates = [
  IraqGovernorate('بغداد', 33.3152, 44.3661),
  IraqGovernorate('البصرة', 30.5085, 47.7804),
  IraqGovernorate('نينوى', 36.3350, 43.1189),
  IraqGovernorate('أربيل', 36.1911, 44.0093),
  IraqGovernorate('النجف', 31.9960, 44.3095),
  IraqGovernorate('كربلاء', 32.6160, 44.0249),
  IraqGovernorate('كركوك', 35.4681, 44.3922),
  IraqGovernorate('الأنبار', 33.4207, 43.3000),
  IraqGovernorate('بابل', 32.4637, 44.4194),
  IraqGovernorate('ذي قار', 31.0578, 46.2580),
  IraqGovernorate('ديالى', 33.7500, 44.6373),
  IraqGovernorate('واسط', 32.5122, 45.8069),
  IraqGovernorate('ميسان', 31.8354, 47.1443),
  IraqGovernorate('المثنى', 31.3234, 45.2949),
  IraqGovernorate('القادسية', 31.9890, 44.9247),
  IraqGovernorate('صلاح الدين', 34.6081, 43.6783),
  IraqGovernorate('دهوك', 36.8617, 42.9951),
  IraqGovernorate('السليمانية', 35.5650, 45.4347),
];

/// المحافظة الأقرب إلى نقطة على الخريطة.
///
/// يُستعمل لتعبئة حقل المحافظة تلقائياً بعد أن يضع المستخدم دبّوسه، بدل
/// مطالبته باختيارها من قائمة من ثمانية عشر بندًا وهو قد حدّد مكانه للتوّ.
///
/// لماذا «أقرب مركز» لا حدود حقيقية؟ لأن الحدود الدقيقة تحتاج مضلّعات
/// ثقيلة أو خدمة عنونة عكسية بمفتاح API وشبكة. وأقرب مركز يصيب داخل
/// المحافظات الواسعة ويخطئ قرب الحدود — وهو خطأ مقبول لأن النتيجة
/// **اقتراح** يراه المستخدم ويصحّحه، لا قيمة تُحفظ من وراء ظهره.
///
/// المسافة إقليدية على الدرجات لا على سطح الكرة: المقارنة بين مراكز
/// متقاربة في العرض نفسه تقريباً، والترتيب لا يتغيّر بإهمال التكوير.
IraqGovernorate nearestGovernorate(LatLng point) {
  IraqGovernorate best = iraqGovernorates.first;
  double bestDistance = double.infinity;

  for (final governorate in iraqGovernorates) {
    final dLat = governorate.lat - point.latitude;
    final dLng = governorate.lng - point.longitude;
    final distance = dLat * dLat + dLng * dLng; // لا حاجة للجذر للمقارنة
    if (distance < bestDistance) {
      bestDistance = distance;
      best = governorate;
    }
  }
  return best;
}
