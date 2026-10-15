import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/chats_provider.dart';
import '../providers/notifications_provider.dart';
import '../services/firebase_phone_auth.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// النصف الثاني من الدخول بـ Google: توثيق رقم الهاتف.
///
/// Google لا يعطينا الرقم — رمزه لا يحمل `phone_number`، وقراءته من People
/// API تحتاج صلاحية يملكها قلّة وتعود فارغة غالباً. فالرقم يُجمع هنا،
/// وتتكفّل Firebase بإرسال الرسالة والتحقّق منها، ثم يُنشئ الخادم الحساب.
///
/// لا حساب قبل هذه الشاشة: الخادم لم يكتب شيئاً بعد. من يخرج من هنا لا
/// يترك خلفه صفّاً لا يستطيع أحد الدخول إليه ولا استرجاعه.
class VerifyPhoneForSignupScreen extends StatefulWidget {
  final String googleIdToken;
  const VerifyPhoneForSignupScreen({super.key, required this.googleIdToken});

  @override
  State<VerifyPhoneForSignupScreen> createState() =>
      _VerifyPhoneForSignupScreenState();
}

class _VerifyPhoneForSignupScreenState
    extends State<VerifyPhoneForSignupScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneAuth = FirebasePhoneAuth();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!isIraqiMobile(phone)) {
      setState(() => _error = 'رقم غير صالح — يبدأ بـ 075 أو 077 أو 078 أو 079');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    // Firebase تشترط E.164 في verifyPhoneNumber، والمستخدم يكتب محلياً.
    final result = await _phoneAuth.sendCode(toE164(phone));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _codeSent = result.success;
      _error = result.success ? null : result.message;
    });
  }

  Future<void> _confirmAndFinish() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'أدخل الرمز المكوّن من 6 أرقام');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final confirmed = await _phoneAuth.confirmCode(code);
    if (!mounted) return;
    if (!confirmed.success || confirmed.idToken == null) {
      setState(() {
        _busy = false;
        _error = confirmed.message;
      });
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.completeSocialSignUpWithPhone(
      googleIdToken: widget.googleIdToken,
      phoneIdToken: confirmed.idToken!,
      notificationsProvider: context.read<NotificationsProvider>(),
      chatsProvider: context.read<ChatsProvider>(),
    );
    if (!mounted) return;

    if (ok) {
      // تُغلق هذه الشاشة وشاشة الدخول تحتها معاً، فيعود المستخدم إلى ما
      // كان يتصفّحه قبل أن يُطلب منه الحساب.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() {
        _busy = false;
        _error = auth.errorMessage ?? 'تعذّر إكمال التسجيل';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('توثيق رقم الهاتف'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.sms_outlined, size: 48, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'خطوة أخيرة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'أدخل الرمز الذي وصلك برسالة نصية'
                    : 'رقم هاتفك هو هويّة حسابك، وبه تستعيده إن نسيت كلمة المرور.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),

              TextField(
                controller: _phoneController,
                enabled: !_codeSent && !_busy,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.right,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.onSurface),
                decoration: _decoration('07XXXXXXXXX', Icons.phone_outlined),
              ),

              if (_codeSent) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    letterSpacing: 8,
                  ),
                  decoration: _decoration('------', Icons.lock_outline)
                      .copyWith(counterText: ''),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed:
                    _busy ? null : (_codeSent ? _confirmAndFinish : _sendCode),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _codeSent ? 'تأكيد وإكمال' : 'أرسل الرمز',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),

              if (_codeSent && !_busy) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _codeSent = false;
                    _codeController.clear();
                    _error = null;
                  }),
                  child: const Text(
                    'تعديل الرقم',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
        prefixIcon: Icon(icon, color: AppColors.onSurfaceVariant),
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}
