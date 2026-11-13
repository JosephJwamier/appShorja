import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';

/// جواب الخادم: أقدم بنية يخدمها، وأين تُحدَّث.
class VersionPolicy {
  final int minBuild;
  final String storeUrl;

  const VersionPolicy({required this.minBuild, required this.storeUrl});

  factory VersionPolicy.fromJson(Map<String, dynamic> json) => VersionPolicy(
        minBuild: (json['min_build'] as num?)?.toInt() ?? 0,
        storeUrl: json['store_url'] as String? ?? '',
      );

  /// هل يجب أن تتوقّف هذه البنية عند شاشة التحديث؟
  ///
  /// بنية مجهولة (0، أي تعذّرت قراءتها) لا تُحجب: الخطأ في قراءة الرقم
  /// لا يجوز أن يقفل التطبيق على صاحبه.
  bool blocks(int currentBuild) => currentBuild > 0 && currentBuild < minBuild;
}

/// رقم البنية كما كُتب في pubspec (`+N`) من versionCode أندرويد.
///
/// `flutter build apk --split-per-abi` لا يضع N بل `1000 × رقم المعمارية
/// + N`: ‏armeabi-v7a ← 1002، و arm64 ← 2002، و x86_64 ← 4002 للبنية 2.
/// بلا هذا لا تُحجب أي APK أبداً، فـ2002 أكبر من أي حدّ أدنى معقول.
/// أما حزمة المتجر (.aab) فتحمل N كما هو، والباقي على 1000 يعطي N في
/// الحالتين ما دامت البنية أقل من 1000.
int normalizeAndroidBuild(int versionCode) => versionCode % 1000;

/// يسأل الخادم عند الإقلاع إن كانت هذه النسخة ما زالت مدعومة.
///
/// **يفشل مفتوحاً**: انقطاع الشبكة، أو مهلة، أو ردّ غريب، كلها تعني
/// «تابع». الحجب لا يقع إلا على جواب صريح من الخادم، وإلا صار انقطاع
/// الإنترنت في بغداد سبباً لقفل التطبيق على من نسخته حديثة أصلاً.
class AppVersionService {
  /// المهلة قصيرة لأن شاشة البدء تنتظرها. خادم بطيء لا يستحق أن يؤخّر كل
  /// إقلاع؛ والنسخة القديمة ستُلتقط في الإقلاع التالي.
  static const _timeout = Duration(seconds: 4);

  Future<VersionPolicy?> fetchPolicy() async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final response = await ApiClient.instance
          .get('/app/version/?platform=$platform', auth: false)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      return VersionPolicy.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  Future<int> currentBuild() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final raw = int.tryParse(info.buildNumber) ?? 0;
      return Platform.isAndroid ? normalizeAndroidBuild(raw) : raw;
    } catch (_) {
      return 0;
    }
  }

  /// الجواب الذي تحتاجه شاشة البدء: سياسة الحجب إن كانت تنطبق، وإلا null.
  Future<VersionPolicy?> blockingPolicy() async {
    final results = await Future.wait([fetchPolicy(), currentBuild()]);
    final policy = results[0] as VersionPolicy?;
    final build = results[1] as int;
    if (policy == null || !policy.blocks(build)) return null;
    return policy;
  }
}
