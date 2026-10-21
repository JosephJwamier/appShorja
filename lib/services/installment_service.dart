import 'dart:convert';

import '../models/installment.dart';
import 'api_client.dart';

/// رفض مُسبَّب من المموّل (أو من الخادم) — لا عطل.
///
/// الفرق ليس تجميلاً: «سقف راتبك لا يكفي» جواب يُعرض قرب حقل البطاقة
/// ويُفيد المشتري، و«تعذّر الاتصال» عطل يُعاد معه المحاولة. الخادم يفصل
/// بينهما بـ 200 مع `eligible: false` مقابل 5xx، وهذا الصنف يحفظ الفصل
/// على هذا الجانب أيضاً.
class InstallmentRefused implements Exception {
  final String message;
  final String code;
  const InstallmentRefused(this.message, {this.code = 'not_eligible'});

  /// العرض انتهى (مرّت مدّة صلاحيته) — المُستدعي يُعيد الفحص بدل أن يعرض
  /// رسالة خطأ لا تقول للمشتري ما يفعله.
  bool get isStaleQuote => code == 'stale_quote' || code == 'terms_changed';

  @override
  String toString() => message;
}

/// نداءات التقسيط. ثلاثة فقط، وعلى نفس نسق [PaymentService]: التطبيق لا
/// يعرف المموّل ولا شروطه، يسأل الخادم عمّا هو متاح.
///
/// رقم البطاقة يُرسل **مرّة واحدة** في [check]، ويعود منه مرجعُ عرض
/// (`reference`) هو كلّ ما يحمله [confirm]. ولا يُحتفظ بالرقم في التطبيق
/// ولا في الخادم (آخر أربعة أرقام فقط) — ولهذا لا يُمرّر هنا إلى أي
/// تسجيل أو تحليلات.
class InstallmentService {
  final _client = ApiClient.instance;

  /// شروط التقسيط المتاحة الآن، أو `null` إن لم يكن هناك مموّل مُهيّأ —
  /// وحينها لا يُعرض زرّ التقسيط أصلاً.
  Future<InstallmentOptions?> fetchOptions() async {
    final response = await _client.get('/installments/options/');
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'];
    if (data is! Map<String, dynamic>) return null;
    return InstallmentOptions.fromJson(data);
  }

  /// فحص البطاقة لهذا الحجز: يُعيد عرضاً فيه الجدول الكامل (قسط شهري،
  /// عدد الأشهر، الإجمالي) ولا يلزم المشتري بشيء ولا يُحرّك مالاً.
  ///
  /// يرمي [InstallmentRefused] للرفض المُسبَّب، و[Exception] للعطل.
  Future<InstallmentPlan> check({
    required int reservationId,
    required String cardNumber,
    int? deliveryLocationId,
  }) async {
    final response = await _client.post(
      '/installments/check/',
      body: {
        'reservation_id': reservationId,
        'card_number': cardNumber,
        'delivery_location_id': ?deliveryLocationId,
      },
    );
    final body = _decode(response.body);
    if (response.statusCode == 200 && body['eligible'] == true) {
      return InstallmentPlan.fromJson(body['data'] as Map<String, dynamic>);
    }
    if (response.statusCode == 200) {
      throw InstallmentRefused(
        _message(body, 'البطاقة غير مؤهّلة للتقسيط'),
        code: body['code'] as String? ?? 'not_eligible',
      );
    }
    throw Exception(_message(body, 'تعذّر فحص التقسيط'));
  }

  /// تأكيد الشراء بالتقسيط: يُنشئ الخطة عند المموّل ويُكمل الحجز في نداء
  /// واحد — مكافئ `complete` للدفع من المحفظة.
  Future<InstallmentPlan> confirm({required String reference}) async {
    final response = await _client.post(
      '/installments/confirm/',
      body: {'reference': reference},
    );
    final body = _decode(response.body);
    if (response.statusCode == 200 && body['data'] != null) {
      return InstallmentPlan.fromJson(body['data'] as Map<String, dynamic>);
    }
    if (response.statusCode == 200 || response.statusCode == 400) {
      throw InstallmentRefused(
        _message(body, 'تعذّر إتمام التقسيط'),
        code: body['code'] as String? ?? 'not_eligible',
      );
    }
    throw Exception(_message(body, 'تعذّر إتمام التقسيط'));
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _message(Map<String, dynamic> body, String fallback) {
    final message = body['message'];
    return message is String && message.isNotEmpty ? message : fallback;
  }
}
