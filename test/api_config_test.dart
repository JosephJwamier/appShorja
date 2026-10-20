// نسختان شُحنتا وهما تشيران إلى `10.0.2.2:8000` — عنوان محاكي أندرويد
// لحاسوب المطوّر. الـAPK كانت سليمة وموقّعة وتفشل على كل هاتف حقيقي
// برسالة «لا يوجد اتصال بالإنترنت»، لأن `flutter build apk` بلا
// `--dart-define` يأخذ القيم الافتراضية.
//
// لا شيء كان يكشف ذلك: لا المحلّل ولا الاختبارات ولا حجم الملف. فهذا
// الملف يحرس الافتراض نفسه.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/config/api_config.dart';

void main() {
  test('الافتراض يشير إلى الإنتاج لا إلى جهاز المطوّر', () {
    expect(ApiConfig.isLocalDevHost, isFalse,
        reason: 'بناء بلا --dart-define يجب أن يصيب الإنتاج');
    expect(ApiConfig.host, 'api.shorjeh.com');
  });

  test('الاتصال مُشفّر افتراضياً', () {
    expect(ApiConfig.scheme, 'https');
    expect(ApiConfig.baseUrl, 'https://api.shorjeh.com/api');
  });

  test('المقبس يتبع المخطّط', () {
    // ws على http و wss على https — ومقبس غير مشفّر إلى خادم https يُرفض.
    expect(ApiConfig.wsScheme, 'wss');
    expect(ApiConfig.wsUrl('/ws/live/1/'), 'wss://api.shorjeh.com/ws/live/1/');
  });

  test('روابط الوسائط بلا مسار api', () {
    expect(ApiConfig.mediaBaseUrl, 'https://api.shorjeh.com');
  });
}
