import '../config/api_config.dart';

/// المضيف المحلّي في بداية الرابط — بأي مخطّط ومنفذ.
///
/// `10.0.2.2` ضمنه: لو أعاد خادمٌ محلّي رابطاً بعنوان المحاكي، فالمضيف
/// الصحيح يبقى هو المضبوط في [ApiConfig] لا المكتوب في الرابط.
/// النظرة الأمامية `(?=[/?#]|$)` تُنهي المضيف عند حدّه.
/// بدونها يُطابق `localhost` بدايةَ `localhost.example.com` — وهو مضيف
/// حقيقي — فيصير الرابط `api.shorjeh.com.example.com`.
final _localHost = RegExp(
    r'^https?://(?:localhost|127\.0\.0\.1|10\.0\.2\.2)(?::\d+)?(?=[/?#]|$)');

/// يُصلح روابط الوسائط التي يبنيها الخادم بعنوانه هو.
///
/// Django يبني روابط مطلقة من المضيف الذي وصله الطلب. في الإنتاج هذا
/// `api.shorjeh.com` فالرابط سليم ويمرّ كما هو. وفي التطوير قد يكون
/// `localhost`، وهو داخل المحاكي يشير إلى المحاكي نفسه لا إلى الخادم —
/// فيُستبدل بما بُني عليه التطبيق فعلاً.
///
/// كانت الوجهة مكتوبة بخط اليد (`10.0.2.2`)، فتظلّ النسخة المُوزَّعة تحمل
/// عنوان جهاز المطوّر. صارت من [ApiConfig]، فتتبع ما بُني عليه التطبيق
/// بلا أن يتذكّرها أحد.
///
/// ويُستبدل المضيف المحلّي وحده: روابط الريلز تأتي من نطاق Cloudflare R2
/// المستقلّ، وإعادة بنائها جميعاً على مضيف الـAPI كانت ستكسرها.
String fixMediaUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  return url.replaceFirst(_localHost, ApiConfig.mediaBaseUrl);
}

/// عدد أيام بصيغة عربية صحيحة (مفرد/جمع) — مثال: 1 -> "يوم واحد"، 3 -> "3 أيام".
String formatDaysAr(int n) => n == 1 ? 'يوم واحد' : '$n أيام';

/// وقت نسبي مختصر بالعربية (الآن / منذ N دقيقة / ساعة / يوم) — موحّد هنا
/// بدل تكراره محلياً في كل شاشة تعرض "قائمة" زمنية (المحادثات، الإشعارات...).
String relativeTimeAr(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'الآن';
  if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
  return 'منذ ${diff.inDays} يوم';
}

/// وقت بصيغة 24 ساعة (مثال 14:05) — لتوقيت كل فقاعة رسالة في المحادثة.
String shortTime(DateTime dt) {
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// تسمية اليوم لفاصل التاريخ بين الرسائل: "اليوم" / "أمس" / تاريخ كامل.
String dayLabelAr(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays == 0) return 'اليوم';
  if (diffDays == 1) return 'أمس';
  return '${local.day}/${local.month}/${local.year}';
}

/// رقم بفواصل الآلاف بدون رمز عملة — للعروض المنقسمة (رقم + IQD منفصلَين)
String formatNum(double amount) {
  final intPart = amount.truncate().abs();
  final intStr = intPart.toString();
  final buf = StringBuffer();
  int count = 0;
  for (int i = intStr.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write(',');
    buf.write(intStr[i]);
    count++;
  }
  return buf.toString().split('').reversed.join();
}

/// يحوّل رقم واتساب محلي عراقي (يبدأ بصفر، مثال 07801706402) إلى الصيغة
/// الدولية التي يتطلبها رابط wa.me (بدون '+' وبدون الصفر البادئ، مثال
/// 9647801706402). يترك الرقم كما هو إن كان يحمل رمز الدولة 964 مسبقاً.
String toWhatsappDigits(String phone) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.startsWith('964')) return digits;
  if (digits.startsWith('0')) return '964${digits.substring(1)}';
  return '964$digits';
}

/// نفس التطبيع أعلاه لكن بصيغة E.164 الكاملة (بعلامة '+')، وهي ما تشترطه
/// Firebase Phone Auth في `verifyPhoneNumber`. مفصولة عن [toWhatsappDigits]
/// لأن رابط wa.me هو الوحيد الذي يريد الأرقام بلا '+'.
String toE164(String phone) => '+${toWhatsappDigits(phone)}';

String formatIqd(double amount) {
  final intPart = amount.truncate().abs();
  final intStr = intPart.toString();
  final buf = StringBuffer();
  int count = 0;
  for (int i = intStr.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write(',');
    buf.write(intStr[i]);
    count++;
  }
  final whole = buf.toString().split('').reversed.join();
  final isWhole = (amount - amount.truncate()) == 0;
  if (isWhole) return 'IQD $whole';
  final frac =
      ((amount - amount.truncate()) * 100).round().toString().padLeft(2, '0');
  return 'IQD $whole.$frac';
}

/// بادئات شركات الاتصال العراقية العاملة: كورك (75)، آسياسيل (77)،
/// زين (78 و79). مطابِقة لـ VALID_MOBILE_PREFIXES في الخادم
/// (core/phone_utils.py) — وأي تغيير هناك يلزمه تغيير هنا.
const _iraqiMobilePrefixes = ['75', '77', '78', '79'];

/// هل هذا رقم موبايل عراقي صالح، بأي صيغة كُتب؟
///
/// الأرضي مرفوض عمداً: الرقم هو هويّة الحساب لأنه يستقبل رسالة التحقّق،
/// والأرضي لا يستقبلها.
bool isIraqiMobile(String phone) {
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);

  final String national;
  if (digits.startsWith('964')) {
    national = digits.substring(3);
  } else if (digits.startsWith('0')) {
    national = digits.substring(1);
  } else {
    national = digits;
  }

  return national.length == 10 &&
      _iraqiMobilePrefixes.any(national.startsWith);
}
