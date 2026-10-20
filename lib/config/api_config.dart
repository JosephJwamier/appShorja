// عنوان الـ API مركزي هنا بدل ما يكون مكرر ومكتوب حرفياً بكل ملف خدمة.
//
// الافتراض هو **الإنتاج**، والتطوير المحلي هو ما يحتاج تمرير قيم:
//
//   flutter run --dart-define=API_HOST=10.0.2.2:8000 --dart-define=API_SCHEME=http
//   flutter build apk --release                    ← يُصيب الإنتاج بلا وسائط
//
// كان الافتراض معكوساً: `10.0.2.2:8000` على `http`، أي عنوان محاكي أندرويد
// لحاسوب المطوّر. ونسيان الوسائط وقت البناء كان يُنتج APK سليمة الشكل
// وموقّعة تماماً، تفشل على كل هاتف حقيقي برسالة «لا يوجد اتصال بالإنترنت» —
// فالعنوان لا وجود له خارج المحاكي. شُحنت نسختان بهذا العطب قبل أن يُكتشف.
//
// الاتجاه الجديد يقلب ثمن النسيان: مطوّر ينسى الوسائط يُصيب الإنتاج فيلاحظ
// فوراً، ونسخة تُبنى للتوزيع تُصيب الإنتاج وهو المطلوب. أسوأ ما يحدث خطأ
// مرئي في التطوير، بدل عطب صامت عند المستخدم.
class ApiConfig {
  const ApiConfig._();

  static const String host = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'api.shorjeh.com',
  );

  static const String scheme = String.fromEnvironment(
    'API_SCHEME',
    defaultValue: 'https',
  );

  /// مثال: https://api.shorjeh.com/api أو http://10.0.2.2:8000/api
  static const String baseUrl = '$scheme://$host/api';

  /// لبناء روابط الوسائط (صور المتاجر... إلخ) بدون مسار /api.
  static const String mediaBaseUrl = '$scheme://$host';

  static const String wsScheme = scheme == 'https' ? 'wss' : 'ws';

  /// [path] لازم يبدأ بـ '/' مثل '/ws/chat/1/?token=...'.
  static String wsUrl(String path) => '$wsScheme://$host$path';

  /// هل نحن على الإعداد المحلي؟ تُستعمل في الاختبار للتأكّد أن نسخة
  /// الإصدار لا تُشحن وهي تشير إلى جهاز المطوّر.
  static bool get isLocalDevHost =>
      host.contains('10.0.2.2') || host.contains('localhost') ||
      host.contains('127.0.0.1');
}
