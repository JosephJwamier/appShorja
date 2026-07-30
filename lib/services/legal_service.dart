import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../models/legal_document.dart';
import 'api_client.dart';

/// خدمة النظام القانوني: جلب الوثائق، فتح الصفحات العلنية، وتسجيل الموافقة.
class LegalService {
  final _client = ApiClient.instance;

  /// رابط الصفحة العلنية للوثيقة (نفس الرابط المطلوب لمتاجر التطبيقات).
  String pageUrl(String docType, {String lang = 'ar'}) =>
      '${ApiConfig.mediaBaseUrl}/legal/$docType/?lang=$lang';

  /// يفتح الوثيقة في متصفّح داخل التطبيق. يرجع true عند النجاح.
  Future<bool> openPage(String docType, {String lang = 'ar'}) async {
    final uri = Uri.parse(pageUrl(docType, lang: lang));
    try {
      return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  /// النسخة الحالية من وثيقة (اختياري — للعرض داخل التطبيق).
  Future<LegalDocument?> fetchCurrent(String docType, {String lang = 'ar'}) async {
    final res = await _client.get(
      '/legal/documents/current/?type=$docType&lang=$lang',
      auth: false,
    );
    if (res.statusCode != 200) return null;
    return LegalDocument.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// الوثائق التي تنتظر موافقة المستخدم الحالي (يتطلب تسجيل دخول).
  Future<List<LegalDocument>> fetchPending({String lang = 'ar'}) async {
    final res = await _client.get('/legal/documents/pending/?lang=$lang');
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['pending'] as List?) ?? const [];
    return list
        .map((e) => LegalDocument.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// تسجيل موافقة المستخدم على الوثائق الحالية (أو وثائق محددة عبر [ids]).
  Future<bool> accept({String lang = 'ar', List<int>? ids}) async {
    try {
      final res = await _client.post(
        '/legal/documents/accept/',
        body: {
          if (ids != null && ids.isNotEmpty) 'ids': ids,
          'lang': lang,
        },
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
