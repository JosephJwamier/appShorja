/// تقييم قوة كلمة المرور — بما يطابق ما يفرضه الخادم فعلاً.
///
/// القواعد هنا ليست رأياً في الأمان، بل انعكاس لمُدقِّقات Django الأربعة
/// في `AUTH_PASSWORD_VALIDATORS`:
///
///   MinimumLengthValidator          → ثمانية أحرف
///   NumericPasswordValidator        → ليست أرقاماً فقط
///   CommonPasswordValidator         → ليست من الشائعات
///   UserAttributeSimilarityValidator→ لا تشبه الاسم أو البريد أو الرقم
///
/// وهذا هو الشرط الذي يجعل المقياس مفيداً: مقياسٌ يقول «قوية» ثم يرفضها
/// الخادم أسوأ من لا مقياس — فالمستخدم يثق به مرّة واحدة ثم لا يثق أبداً.
library;

enum PasswordStrength {
  /// لا شيء مكتوب بعد.
  none,

  /// الخادم سيرفضها.
  weak,

  /// مقبولة: تمرّ، ولا أكثر.
  fair,

  /// جيّدة.
  good,

  /// قوية.
  strong,
}

/// حكم على كلمة مرور: درجتها، وهل تمرّ على الخادم، والخطوة التالية الأنفع.
class PasswordVerdict {
  final PasswordStrength strength;

  /// `true` إن كانت تستوفي ما يفرضه الخادم — فيُسمح بإرسال النموذج.
  final bool meetsMinimum;

  /// سطر واحد يقول ما ينقصها، أو `null` حين لا ينقصها شيء.
  ///
  /// واحدٌ لا قائمة: قائمة شروط تُقرأ كامتحان، وسطرٌ واحد يُقرأ كخطوة.
  final String? hint;

  const PasswordVerdict({
    required this.strength,
    required this.meetsMinimum,
    this.hint,
  });
}

const int kMinPasswordLength = 8;

/// أكثر ما يُكتب فعلاً — لا قائمة Django كاملة (عشرون ألف كلمة لا تُحمَل في
/// تطبيق)، بل ما يُلتقط منها هنا قبل رحلة إلى الخادم. والخادم يبقى الحكم.
const _commonPasswords = <String>{
  '12345678', '123456789', '1234567890', 'password', 'password1',
  'password123', 'qwerty123', 'qwertyui', '11111111', '00000000',
  'abcd1234', 'a1234567', 'iloveyou', 'admin123', 'welcome1',
  'letmein1', 'football', 'baseball', 'sunshine', 'princess',
  'shorjeh', 'shorja123', 'iraq1234', 'baghdad1', 'baghdad123',
};

/// يُقيّم [password]، و[personal] هي ما كتبه المستخدم عن نفسه في النموذج
/// (الاسم، البريد، الهاتف) كي لا تُقبل كلمة مرور مبنيّة عليها.
PasswordVerdict ratePassword(
  String password, {
  Iterable<String> personal = const [],
}) {
  if (password.isEmpty) {
    return const PasswordVerdict(
        strength: PasswordStrength.none, meetsMinimum: false);
  }

  if (password.length < kMinPasswordLength) {
    final missing = kMinPasswordLength - password.length;
    return PasswordVerdict(
      strength: PasswordStrength.weak,
      meetsMinimum: false,
      hint: 'أضف $missing ${missing == 1 ? 'حرفاً' : 'أحرف'} على الأقل',
    );
  }

  if (RegExp(r'^\d+$').hasMatch(password)) {
    return const PasswordVerdict(
      strength: PasswordStrength.weak,
      meetsMinimum: false,
      hint: 'أرقام فقط — أضف حروفاً',
    );
  }

  if (_commonPasswords.contains(password.toLowerCase())) {
    return const PasswordVerdict(
      strength: PasswordStrength.weak,
      meetsMinimum: false,
      hint: 'كلمة مرور شائعة جداً — اختر غيرها',
    );
  }

  if (_looksPersonal(password, personal)) {
    return const PasswordVerdict(
      strength: PasswordStrength.weak,
      meetsMinimum: false,
      hint: 'لا تستعمل اسمك أو رقمك أو بريدك',
    );
  }

  // تجاوزت ما يرفضه الخادم. ما بعدها درجات لا شروط.
  final hasLetters = RegExp(r'[A-Za-z؀-ۿ]').hasMatch(password);
  final hasDigits = RegExp(r'\d').hasMatch(password);
  final hasSymbols = RegExp(r'[^A-Za-z0-9؀-ۿ]').hasMatch(password);

  var score = 0;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (hasLetters && hasDigits) score++;
  if (hasSymbols) score++;

  if (score >= 3) {
    return const PasswordVerdict(
        strength: PasswordStrength.strong, meetsMinimum: true);
  }
  if (score >= 2) {
    return const PasswordVerdict(
        strength: PasswordStrength.good, meetsMinimum: true);
  }
  return PasswordVerdict(
    strength: PasswordStrength.fair,
    meetsMinimum: true,
    // تمرّ، فالتلميح اقتراح لا شرط — ولهذا يُذكر ما يرفعها لا ما يمنعها.
    hint: hasLetters && hasDigits
        ? 'أطول = أقوى'
        : 'امزج حروفاً وأرقاماً',
  );
}

/// هل بُنيت كلمة المرور على بيانات المستخدم نفسه؟
///
/// ليست محاكاةً دقيقة لـ`UserAttributeSimilarityValidator` — تلك تستعمل
/// `SequenceMatcher` بنسبة 0.7 — بل التقاطٌ للحالة الشائعة قبل رحلة إلى
/// الخادم: أن تحتوي كلمة المرور قطعةً من اسمه أو بريده أو رقمه.
///
/// والحدّ أربعة محارف: أقلّ منها يُطابق مصادفةً («علي» داخل أي كلمة)،
/// فيُرفض ما لا ذنب له.
bool _looksPersonal(String password, Iterable<String> personal) {
  final lower = password.toLowerCase();
  for (final raw in personal) {
    for (final token in _tokensOf(raw)) {
      if (token.length < 4) continue;
      if (lower.contains(token) || token.contains(lower)) return true;
    }
  }
  return false;
}

/// قطع قابلة للمقارنة من حقل واحد.
///
/// الهاتف يُعطي أيضاً أواخره: `07701234567` كلمةُ مرورٍ سيئة، و`1234567`
/// منه مثلها — ومن يبني كلمة مرور على رقمه يأخذ آخره غالباً لا أوّله.
Iterable<String> _tokensOf(String raw) sync* {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return;

  for (final part in value.split(RegExp(r'[\s@._\-+]+'))) {
    if (part.isNotEmpty) yield part;
  }

  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 7) {
    yield digits;
    yield digits.substring(digits.length - 7);
  }
}
