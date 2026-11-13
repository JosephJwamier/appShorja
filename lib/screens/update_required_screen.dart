import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_version_service.dart';
import '../theme/app_colors.dart';

/// تظهر بدل التطبيق كلّه حين تكون هذه النسخة أقدم مما يخدمه الخادم.
///
/// بلا زرّ «لاحقاً» عمداً: الحدّ الأدنى يُرفع فقط حين تكون النسخة القديمة
/// معطوبة فعلاً أمام الخادم الحالي. وتجاوز الشاشة لا يعيدها سليمة، بل
/// يُوصل صاحبها إلى أول شاشة تنهار.
class UpdateRequiredScreen extends StatelessWidget {
  final VersionPolicy policy;

  const UpdateRequiredScreen({super.key, required this.policy});

  @override
  Widget build(BuildContext context) {
    final hasStore = policy.storeUrl.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.system_update_rounded,
                  size: 72, color: AppColors.primary),
              const SizedBox(height: 24),
              const Text(
                'يتوفّر تحديث مطلوب',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                hasStore
                    ? 'هذه النسخة من التطبيق لم تعد تعمل مع الخدمة. حدّث '
                        'التطبيق لتتابع الشراء والحجز والبثّ.'
                    : 'هذه النسخة من التطبيق لم تعد تعمل مع الخدمة. ثبّت '
                        'أحدث نسخة لتتابع.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: AppColors.onSurfaceVariant),
              ),
              if (hasStore) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => launchUrl(Uri.parse(policy.storeUrl),
                        mode: LaunchMode.externalApplication),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('حدّث الآن', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
