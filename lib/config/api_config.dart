// عنوان الـ API مركزي هنا بدل ما يكون مكرر ومكتوب حرفياً بكل ملف خدمة.
// للتشغيل على بيئة مختلفة (dev/staging/production) أو مع HTTPS مرّر القيم
// وقت التشغيل/البناء عبر --dart-define بدون تعديل الكود:
//   flutter run --dart-define=API_HOST=10.0.2.2:8000 --dart-define=API_SCHEME=http
//   flutter build apk --dart-define=API_HOST=api.shorjeh.com --dart-define=API_SCHEME=https
//
// القيم الافتراضية (بدون أي --dart-define) تبقى مطابقة لمحاكي Android الحالي
// حتى لا ينكسر التطوير المحلي.
class ApiConfig {
  const ApiConfig._();

  static const String host = String.fromEnvironment(
    'API_HOST',
    defaultValue: '10.0.2.2:8000',
  );

  static const String scheme = String.fromEnvironment(
    'API_SCHEME',
    defaultValue: 'http',
  );

  /// مثال: http://10.0.2.2:8000/api أو https://api.shorjeh.com/api
  static const String baseUrl = '$scheme://$host/api';

  /// لبناء روابط الوسائط (صور المتاجر... إلخ) بدون مسار /api.
  static const String mediaBaseUrl = '$scheme://$host';

  static const String wsScheme = scheme == 'https' ? 'wss' : 'ws';

  /// [path] لازم يبدأ بـ '/' مثل '/ws/chat/1/?token=...'.
  static String wsUrl(String path) => '$wsScheme://$host$path';
}
