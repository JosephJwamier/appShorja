import 'package:geolocator/geolocator.dart';

/// سبب تعذّر الحصول على الموقع — ولكلٍّ علاج مختلف.
///
/// `bool` واحد كان يخلط ثلاث حالات لا يجمعها شيء: من أطفأ خدمة الموقع
/// يحتاج إعدادات النظام، ومن رفض نهائياً يحتاج إعدادات التطبيق، ومن رفض
/// مرّة يكفيه أن يُسأل ثانية. وبلا تمييزها تصمت الخريطة في الحالات الثلاث.
enum GpsDenial {
  none,

  /// خدمة الموقع مطفأة على مستوى الجهاز — لا يُسأل المستخدم أصلاً.
  serviceOff,

  /// رُفض هذه المرّة، ويمكن أن يُسأل ثانية.
  denied,

  /// رُفض نهائياً: أندرويد لا يعرض الحوار بعدها إطلاقاً، والعلاج الوحيد
  /// إعدادات التطبيق. هذه أكثر حالة تبدو كعطل — لا حوار ولا رسالة.
  deniedForever,
}

class GpsService {
  /// يطلب الإذن ويقول لماذا فشل إن فشل.
  Future<GpsDenial> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return GpsDenial.serviceOff;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return GpsDenial.none;
      case LocationPermission.deniedForever:
        return GpsDenial.deniedForever;
      default:
        return GpsDenial.denied;
    }
  }

  Future<bool> requestPermission() async =>
      await ensurePermission() == GpsDenial.none;

  Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// يفتح إعدادات الموقع في النظام (لحالة serviceOff).
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// يفتح صفحة التطبيق في الإعدادات (لحالة deniedForever).
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<Position?> getCurrentPosition() async {
    try {
      if (await ensurePermission() != GpsDenial.none) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }
}
