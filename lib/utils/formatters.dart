/// Rewrites localhost media URLs to the Android-emulator host address.
/// The Django backend returns absolute URLs using its own hostname (localhost),
/// but inside the emulator that address points to the emulator itself.
String fixMediaUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  return url
      .replaceFirst('http://localhost:', 'http://10.0.2.2:')
      .replaceFirst('https://localhost:', 'https://10.0.2.2:');
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
