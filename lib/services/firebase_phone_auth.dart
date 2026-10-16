import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../utils/formatters.dart';

/// إرسال رمز التحقق برسالة نصية والتأكّد منه عبر Firebase Phone Auth.
///
/// لماذا انتقل التحقّق إلى العميل: Firebase لا تملك واجهة لإرسال رسالة نصية
/// اعتباطية — لا يمكن أن يولّد الخادم رمزاً ثم «يرسله عبر Firebase». خدمة
/// Phone Auth تولّد الرمز وترسله بنفسها من داخل التطبيق، ثم تُرجع ID token
/// يحمل مطالبة `phone_number` موثّقة. لذا صار الخادم يتحقّق من التوكن بدل أن
/// يولّد الرمز — ويتحقّق الخادم من الرمز الناتج، وهو نفس النمط الذي
/// تستعمله `VerifyPhoneView` و`ResetPasswordByPhoneView`.
///
/// الحالة (`verificationId`) تعيش داخل نسخة واحدة من هذا الصنف بين الإرسال
/// والتأكيد، فاحتفظ بالنسخة نفسها طوال جلسة التحقّق الواحدة.
class FirebasePhoneAuth {
  final FirebaseAuth _auth;

  FirebasePhoneAuth({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  /// مهلة أمان حول [FirebaseAuth.verifyPhoneNumber]: على أندرويد ترجع الدالة
  /// فوراً وتصل النتيجة عبر ردود النداء، فإن لم يصل أي ردّ (شبكة ميتة مثلاً)
  /// تبقى الورقة تدور بلا نهاية. 90 ثانية أطول من مهلة الاسترجاع التلقائي
  /// المعتادة (60 ثانية) بهامش كافٍ.
  static const _sendTimeout = Duration(seconds: 90);

  /// يطلب من Firebase إرسال رمز إلى [phone]. يقبل الرقم بصيغته المحلية
  /// (07xxxxxxxxx) أو الدولية ويحوّله إلى E.164 التي تشترطها Firebase.
  Future<({bool success, String message})> sendCode(String phone) async {
    // في بناء التطوير فقط: تجاوز Play Integrity إلى تحقّق reCAPTCHA.
    //
    // Play Integrity لا يتعرّف إلا على تطبيق وزّعته Google Play، فالبناء
    // المثبَّت يدوياً (debug على محاكي أو جهاز) يُصدر رمزاً بلا معلومات تطبيق
    // صالحة وترفضه Firebase بـ «17028 Invalid app info» مهما كانت الحزمة
    // وبصمات SHA صحيحة — وهي كذلك. reCAPTCHA مسار تحقّق بديل تدعمه Firebase
    // ولا يشترط التوزيع عبر Play، فيُتيح اختبار رقم حقيقي أثناء التطوير.
    //
    // مقصور على kDebugMode عمداً: في الإصدار يبقى Play Integrity هو المتحقّق،
    // فهو الأقوى ولا يعرض للمستخدم أي حاجز.
    if (kDebugMode) {
      try {
        await _auth.setSettings(forceRecaptchaFlow: true);
      } catch (_) {
        // إعداد اختياري للتطوير — فشله لا يمنع المحاولة عبر المسار الافتراضي.
      }
    }

    final e164 = toE164(phone);
    final completer = Completer<({bool success, String message})>();

    void complete(({bool success, String message}) result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    _auth.verifyPhoneNumber(
      phoneNumber: e164,
      // يجعل «إعادة الإرسال» إرسالاً جديداً فعلياً بدل أن ترفضه Firebase
      // بوصفه تكراراً للطلب الأول.
      forceResendingToken: _resendToken,
      timeout: const Duration(seconds: 60),
      // الاسترجاع التلقائي على أندرويد: نتجاهله عمداً ونترك المستخدم يكتب
      // الرمز، لأن ورقة إدخال الرمز لا تملك طريقة لتغلق نفسها من هنا. الرمز
      // يصل بالرسالة في كل الأحوال، فالمسار اليدوي يعمل دائماً.
      verificationCompleted: (_) {},
      verificationFailed: (e) =>
          complete((success: false, message: _arabicError(e))),
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        complete((success: true, message: 'تم إرسال رمز التحقق إلى $e164'));
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    ).catchError((Object e) {
      complete((
        success: false,
        message: e is FirebaseAuthException
            ? _arabicError(e)
            : 'تعذّر إرسال رمز التحقق، تحقّق من اتصالك بالإنترنت',
      ));
    });

    return completer.future.timeout(
      _sendTimeout,
      onTimeout: () =>
          (success: false, message: 'انتهت المهلة دون وصول ردّ من الخادم'),
    );
  }

  /// يؤكّد الرمز مع Firebase ويُرجع ID token يحمل `phone_number` موثّقاً،
  /// وهو ما يرسله المتّصل إلى الخادم كبرهان على ملكية الرقم.
  Future<({bool success, String? idToken, String message})> confirmCode(
    String smsCode,
  ) async {
    final verificationId = _verificationId;
    if (verificationId == null) {
      return (
        success: false,
        idToken: null,
        message: 'لم يُرسل رمز بعد — اضغط «إعادة إرسال الرمز»',
      );
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    try {
      final userCredential = await _attachCredential(credential);
      // getIdToken(true): بعد ربط الرقم بحساب Firebase قائم يبقى التوكن
      // المخزَّن بلا مطالبة phone_number حتى يُجدَّد، فيرفضه الخادم بلا سبب
      // ظاهر. التحديث القسري يضمن أن التوكن المُرسَل يحمل الرقم فعلاً.
      final idToken = await userCredential.user?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        return (
          success: false,
          idToken: null,
          message: 'تعذّر إتمام التحقّق، حاول مرة أخرى',
        );
      }
      return (success: true, idToken: idToken, message: 'تم التحقّق من الرمز');
    } on FirebaseAuthException catch (e) {
      return (success: false, idToken: null, message: _arabicError(e));
    } catch (_) {
      return (
        success: false,
        idToken: null,
        message: 'تعذّر إتمام التحقّق، حاول مرة أخرى',
      );
    }
  }

  /// يربط الرقم بحساب Firebase الحالي إن وُجد (مستخدم سجّل دخوله بجوجل مثلاً)
  /// بدل استبداله بحساب هاتف منفصل. وإن كان الرقم مرتبطاً بحساب آخر أصلاً
  /// نسجّل الدخول به مباشرة — فالغرض هنا إثبات ملكية الرقم لا إدارة حسابات
  /// Firebase، وجلسة التطبيق الحقيقية هي JWT الصادر عن خادمنا.
  Future<UserCredential> _attachCredential(PhoneAuthCredential credential) async {
    final current = _auth.currentUser;
    if (current == null) return _auth.signInWithCredential(credential);

    try {
      return await current.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked' ||
          e.code == 'credential-already-in-use' ||
          e.code == 'account-exists-with-different-credential') {
        return _auth.signInWithCredential(credential);
      }
      rethrow;
    }
  }

  /// رسائل عربية للأخطاء الشائعة. الحالتان الأخيرتان تحديداً تعنيان أن إعداد
  /// المشروع في Firebase ناقص (مزوّد الهاتف غير مفعّل، أو بصمة SHA غير
  /// مسجّلة) — وهما أكثر ما يظهر عند أول تشغيل، فتسميتهما بوضوح توفّر ساعات.
  String _arabicError(FirebaseAuthException e) {
    // Firebase تُغلّف عدّة أسباب مختلفة تماماً داخل `operation-not-allowed`
    // وتترك السبب الفعلي في نصّ الرسالة وحده. أهمّها حظر المنطقة (17006):
    // المزوّد مفعّل، لكن سياسة مناطق الرسائل لا تسمح برمز الدولة المطلوب —
    // وهو ما لا تدلّ عليه رسالة «المزوّد غير مفعّل» إطلاقاً.
    final detail = e.message ?? '';
    if (detail.contains('17006') || detail.contains('region')) {
      return 'إرسال الرسائل إلى هذه الدولة غير مسموح في إعدادات المشروع '
          '(SMS Region Policy)';
    }
    return _codeError(e);
  }

  String _codeError(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'رقم الهاتف غير صالح',
        'invalid-verification-code' => 'الرمز غير صحيح',
        'invalid-verification-id' ||
        'session-expired' =>
          'انتهت صلاحية الرمز — اطلب رمزاً جديداً',
        'too-many-requests' =>
          'محاولات كثيرة من هذا الجهاز — انتظر قليلاً ثم أعد المحاولة',
        'quota-exceeded' => 'تجاوز المشروع حصّة الرسائل النصية اليومية',
        'operation-not-allowed' =>
          'مزوّد الهاتف غير مفعّل في مشروع Firebase',
        'missing-client-identifier' ||
        'app-not-authorized' =>
          'هذا التطبيق غير مُصرّح له في مشروع Firebase (بصمة SHA ناقصة)',
        'network-request-failed' => 'تعذّر الاتصال بالإنترنت',
        _ => e.message ?? 'تعذّر إرسال رمز التحقق',
      };
}
