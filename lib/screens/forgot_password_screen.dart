import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'package:flutter/services.dart';
import '../utils/formatters.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _service = AuthService();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  /// الهاتف هو الافتراضي: البريد اختياري عند التسجيل، فأكثر الحسابات بلا
  /// عنوان يصلها عليه رمز. من سجّل ببريد يجده خلف المبدّل.
  bool _byPhone = true;

  int _step = 0; // 0 = enter identifier, 1 = enter code + new password
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (_byPhone) return _requestCodeByPhone();
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'أدخل بريداً إلكترونياً صحيحاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _service.requestPasswordResetCode(email: email);
    if (!mounted) return;
    // لا نتقدّم إلى خطوة الرمز إلا إن كان هناك رمزٌ قادم فعلاً.
    if (!result.success) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    setState(() {
      _busy = false;
      _info = result.message;
      _step = 1;
    });
  }

  Future<void> _confirmReset() async {
    if (_byPhone) return _confirmResetByPhone();
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    if (code.length != 6) {
      setState(() => _error = 'أدخل الرمز المكوّن من 6 أرقام');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _error = 'يجب ألا تقل كلمة المرور عن 8 أحرف');
      return;
    }
    if (newPassword != _confirmController.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await _service.confirmPasswordReset(
      email: _emailController.text.trim(),
      code: code,
      newPassword: newPassword,
      newPassword2: _confirmController.text,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message), backgroundColor: AppColors.success),
    );
    Navigator.pop(context);
  }

  Future<void> _requestCodeByPhone() async {
    final phone = _phoneController.text.trim();
    if (!isIraqiMobile(phone)) {
      setState(() => _error = 'رقم غير صالح — يبدأ بـ 075 أو 077 أو 078 أو 079');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // الخادم يطبّع الرقم بنفسه، لكن الإرسال بالصيغة المعيارية يُبقي ما
    // يراه السجلّ مطابقاً لما يُحفظ.
    final result = await _service.sendPhoneCode(phone: toE164(phone));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) {
        _info = result.alreadySent
            ? 'رمز سابق ما زال صالحاً — أدخله'
            : 'أدخل الرمز الذي وصلك عبر واتساب';
        _step = 1;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _confirmResetByPhone() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;
    if (code.length != 6) {
      setState(() => _error = 'أدخل الرمز المكوّن من 6 أرقام');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _error = 'يجب ألا تقل كلمة المرور عن 8 أحرف');
      return;
    }
    if (newPassword != _confirmController.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // نداء واحد: الخادم يتحقّق من الرمز مع Wevlix ويغيّر كلمة المرور في
    // الطلب نفسه. كان هذا خطوتين حين كانت Firebase تتحقّق على الجهاز.
    final result = await _service.resetPasswordByCode(
      phone: toE164(_phoneController.text.trim()),
      code: code,
      newPassword: newPassword,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message), backgroundColor: AppColors.success),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('نسيت كلمة المرور'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _step == 0 ? _emailStep() : _resetStep(),
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('برقم الهاتف'),
              icon: Icon(Icons.sms_outlined),
            ),
            ButtonSegment(
              value: false,
              label: Text('بالبريد'),
              icon: Icon(Icons.mail_outline),
            ),
          ],
          selected: {_byPhone},
          onSelectionChanged: _busy
              ? null
              : (selection) => setState(() {
                    _byPhone = selection.first;
                    // الخطأ يخصّ الطريقة السابقة، فلا معنى لبقائه معروضاً
                    // فوق حقل مختلف.
                    _error = null;
                  }),
        ),
        const SizedBox(height: 20),
        Text(
          _byPhone
              ? 'أدخل رقم هاتفك وسيصلك رمز برسالة نصية'
              : 'أدخل بريدك الإلكتروني وسنرسل لك رمزاً لإعادة تعيين كلمة المرور',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (_byPhone)
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textAlign: TextAlign.right,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              hintText: '07XXXXXXXXX',
              border: OutlineInputBorder(),
            ),
          )
        else
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
              border: OutlineInputBorder(),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _busy ? null : _requestCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('إرسال الرمز',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _resetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_info != null) ...[
          Text(_info!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 20),
        ],
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 6),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          obscureText: true,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور الجديدة',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'تأكيد كلمة المرور',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _busy ? null : _confirmReset,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('تعيين كلمة المرور الجديدة',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: const Text('تغيير البريد الإلكتروني'),
        ),
      ],
    );
  }
}
