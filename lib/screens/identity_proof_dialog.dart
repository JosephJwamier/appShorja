import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'verify_code_sheet.dart';

/// Asks whoever holds the phone to show it is their account: the password, or
/// a WhatsApp code sent to [phone], the number the account has now. Returns the
/// fields to send with the request, or null when they backed out.
Future<Map<String, String>?> askIdentityProof(
  BuildContext context, {
  required String phone,
}) async {
  final answer = await showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(canUseCode: phone.isNotEmpty),
  );
  if (answer == null) return null;
  if (answer.isNotEmpty) return {'current_password': answer};
  if (!context.mounted) return null;

  String? typed;
  final done = await showVerifyCodeSheet(
    context,
    title: 'تأكيد هويتك',
    subtitle: 'أرسلنا رمزاً مكوّناً من 6 أرقام عبر واتساب إلى $phone',
    onSendCode: () async {
      final r = await AuthService().sendPhoneCode(phone: phone);
      return (success: r.success, message: r.message);
    },
    // The server judges it together with the change itself: a code is spent
    // the moment it is checked.
    onVerifyCode: (code) async {
      typed = code;
      return (success: true, message: '');
    },
  );
  return done == true && typed != null ? {'code': typed!} : null;
}

/// Pops the password, or '' when they chose the code instead.
class _PasswordDialog extends StatefulWidget {
  final bool canUseCode;
  const _PasswordDialog({required this.canUseCode});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isNotEmpty) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تأكيد هويتك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.canUseCode)
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('ليست لديّ كلمة مرور — أرسل رمز واتساب'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(onPressed: _submit, child: const Text('تأكيد')),
        ],
      ),
    );
  }
}
