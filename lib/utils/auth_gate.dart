import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../theme/app_colors.dart';

/// بوابة الإجراءات المحمية.
///
/// التطبيق صار يُفتح للضيوف: يتصفّحون المنتجات والمزادات والريلز بلا حساب.
/// لكن كل ما يكتب أو يحجز أو يزايد أو يراسل يحتاج هوية — وهذه الدالة هي
/// النقطة الوحيدة التي تطلبها.
///
/// تُرجع `true` إن كان المستخدم داخلاً أصلاً، أو إن دخل نتيجة هذا الطلب.
/// نمط الاستعمال:
///
/// ```dart
/// if (!await requireAuth(context, reason: 'لحجز هذا المنتج')) return;
/// ```
///
/// مهم: `reason` تُقال بصيغة «لـ...» لتُقرأ داخل الجملة — فالمستخدم يعرف
/// *لماذا* يُطلب منه الحساب الآن بالذات، لا أنه اصطدم بجدار.
Future<bool> requireAuth(BuildContext context, {String? reason}) async {
  if (context.read<AuthProvider>().isLoggedIn) return true;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _AuthPromptSheet(reason: reason),
  );

  // لا نعتمد على ما تُرجعه الورقة: المستخدم قد يدخل ثم يعود، وقد يُغلقها
  // بالسحب. الحقيقة الوحيدة هي حالة المزوّد بعد انتهاء كل ذلك.
  if (!context.mounted) return false;
  return context.read<AuthProvider>().isLoggedIn;
}

class _AuthPromptSheet extends StatelessWidget {
  final String? reason;
  const _AuthPromptSheet({this.reason});

  Future<void> _go(BuildContext context, Widget screen) async {
    Navigator.pop(context);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.lock_outline, size: 40, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            reason == null ? 'يلزم تسجيل الدخول' : 'سجّل الدخول $reason',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'التصفّح مفتوح للجميع — الحساب يلزم فقط عند التعامل.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _go(context, const LoginScreen()),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text('تسجيل الدخول',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _go(context, const RegisterScreen()),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: AppColors.onSurface,
                side: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text('إنشاء حساب جديد',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('أكمل التصفّح',
                style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
