import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/chats_provider.dart';
import '../theme/app_colors.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final notificationsProvider =
        Provider.of<NotificationsProvider>(context, listen: false);
    final chatsProvider = Provider.of<ChatsProvider>(context, listen: false);
    await authProvider.loginWithGoogle(
      notificationsProvider: notificationsProvider,
      chatsProvider: chatsProvider,
    );
  }

  Future<void> _handleFacebookLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final notificationsProvider =
        Provider.of<NotificationsProvider>(context, listen: false);
    final chatsProvider = Provider.of<ChatsProvider>(context, listen: false);
    await authProvider.loginWithFacebook(
      notificationsProvider: notificationsProvider,
      chatsProvider: chatsProvider,
    );
  }

  Future<void> _handleLogin() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final notificationsProvider =
        Provider.of<NotificationsProvider>(context, listen: false);
    final chatsProvider = Provider.of<ChatsProvider>(context, listen: false);
    await authProvider.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      notificationsProvider: notificationsProvider,
      chatsProvider: chatsProvider,
    );
    // البوّابة (AuthGate) تتولّى الانتقال بعد نجاح الدخول
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // الشعار + الترحيب
                  const _BrandHeader(),

                  const SizedBox(height: 32),

                  // البطاقة البيضاء
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'تسجيل الدخول',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'أدخل بياناتك للوصول إلى حسابك',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // حقل اسم المستخدم / البريد
                        const Text(
                          'اسم المستخدم',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _usernameController,
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppColors.onSurface),
                          decoration: _fieldDecoration(
                            hint: 'اسم المستخدم',
                            icon: Icons.person_outline,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // كلمة المرور + رابط النسيان
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordScreen()),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'نسيت كلمة المرور؟',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const Text(
                              'كلمة المرور',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppColors.onSurface),
                          decoration: _fieldDecoration(
                            hint: '••••••••',
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.onSurfaceVariant,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),

                        // رسالة الخطأ
                        if (auth.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            auth.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // زر الدخول المتدرّج
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryContainer,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.arrow_forward, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'تسجيل الدخول',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // فاصل "أو عبر"
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: AppColors.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'أو عبر',
                                style: TextStyle(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: AppColors.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // زرّا فيسبوك وجوجل (بصريّان فقط)
                        Row(
                          children: [
                            Expanded(
                              child: _SocialButton(
                                label: 'جوجل',
                                icon: Icons.g_mobiledata,
                                iconColor: AppColors.onSurface,
                                onTap:
                                    auth.isLoading ? null : _handleGoogleLogin,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SocialButton(
                                label: 'فيسبوك',
                                icon: Icons.facebook,
                                iconColor: const Color(0xFF1877F2),
                                onTap: auth.isLoading
                                    ? null
                                    : _handleFacebookLogin,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // إنشاء حساب جديد
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: auth.isLoading
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                );
                              },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'إنشاء حساب جديد',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Text(
                        ' ليس لديك حساب؟',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 14, color: AppColors.onSurfaceVariant),
                      SizedBox(width: 6),
                      Text(
                        'معاملات آمنة ومشفّرة 100%',
                        style: TextStyle(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // تنسيق موحّد للحقول بزوايا 8px (كما ينصّ DESIGN.md لحقول البيانات)
  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
      prefixIcon: Icon(icon, color: AppColors.onSurfaceVariant),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.primaryContainer,
          width: 2,
        ),
      ),
    );
  }
}

// الشعار المربّع البرتقاليّ + اسم الشورجة + الترحيب
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryContainer.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.storefront, color: Colors.white, size: 44),
        ),
        const SizedBox(height: 16),
        const Text(
          'الشورجة',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'مرحباً بك في وجهتك الأولى للمزادات والتسوق الحديث',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// زرّ اجتماعيّ (بصريّ فقط، لا خادم له)
class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: AppColors.onSurface,
        side: BorderSide(
          color: AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Icon(icon, color: iconColor, size: 24),
        ],
      ),
    );
  }
}