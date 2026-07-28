import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Generic "enter the 6-digit code we sent you" sheet, reused for both
/// email and phone verification. Sends a fresh code as soon as it opens.
/// Returns true if the code was verified successfully.
Future<bool?> showVerifyCodeSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<({bool success, String message})> Function() onSendCode,
  required Future<({bool success, String message})> Function(String code)
      onVerifyCode,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VerifyCodeSheet(
      title: title,
      subtitle: subtitle,
      onSendCode: onSendCode,
      onVerifyCode: onVerifyCode,
    ),
  );
}

class _VerifyCodeSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<({bool success, String message})> Function() onSendCode;
  final Future<({bool success, String message})> Function(String code)
      onVerifyCode;

  const _VerifyCodeSheet({
    required this.title,
    required this.subtitle,
    required this.onSendCode,
    required this.onVerifyCode,
  });

  @override
  State<_VerifyCodeSheet> createState() => _VerifyCodeSheetState();
}

class _VerifyCodeSheetState extends State<_VerifyCodeSheet> {
  final _codeController = TextEditingController();
  bool _sending = true;
  bool _verifying = false;
  String? _info;
  bool _infoIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _info = null;
    });
    final result = await widget.onSendCode();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _info = result.message;
      _infoIsError = !result.success;
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _info = 'أدخل الرمز المكوّن من 6 أرقام';
        _infoIsError = true;
      });
      return;
    }
    setState(() {
      _verifying = true;
      _info = null;
    });
    final result = await widget.onVerifyCode(code);
    if (!mounted) return;
    if (result.success) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _verifying = false;
      _info = result.message;
      _infoIsError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 6),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.surfaceContainer),
                    ),
                  ),
                ),
                if (_info != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _info!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _infoIsError ? AppColors.error : AppColors.success,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _verifying || _sending ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _verifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('تأكيد',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _sending ? null : _send,
                  child: Text(_sending ? 'جاري الإرسال...' : 'إعادة إرسال الرمز'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
