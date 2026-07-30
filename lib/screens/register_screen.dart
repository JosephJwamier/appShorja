import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chats_provider.dart';
import '../theme/app_colors.dart';
import '../services/legal_service.dart';
import 'interests_selection_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();
  final _legal = LegalService();

  // الموافقة الإلزامية على الشروط وسياسة الخصوصية قبل إنشاء الحساب.
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    // بوابة قانونية: لا يُنشأ الحساب دون موافقة صريحة.
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب الموافقة على شروط الاستخدام وسياسة الخصوصية'),
        ),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final chatsProvider = Provider.of<ChatsProvider>(context, listen: false);
    final success = await auth.register(
      username: _usernameController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
      password2: _password2Controller.text,
      chatsProvider: chatsProvider,
    );

    if (success && mounted) {
      // تسجيل الموافقة على الوثائق الحالية (أفضل جهد — بوابة ConsentGate
      // تلتقط أي إخفاق لاحقاً على أي حال).
      await _legal.accept(lang: 'ar');
    }

    if (success && mounted) {
      // Replace (not push) so popping the interests screen lands back on
      // whatever was under this route — the AuthGate, which by now renders
      // the logged-in shell since auth.isLoggedIn just flipped to true.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const InterestsSelectionScreen()),
      );
    }
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
                  // سهم الرجوع
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios,
                            color: AppColors.primary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // العنوان
                  const Text(
                    'إنشاء حساب',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // البطاقة البيضاء
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.all(Radius.circular(28)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // الاسم الأول
                          TextFormField(
                            controller: _firstNameController,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('الاسم الأول'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'الاسم الأول مطلوب';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // الاسم الثاني
                          TextFormField(
                            controller: _lastNameController,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('الاسم الثاني'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'الاسم الثاني مطلوب';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // اسم المستخدم
                          TextFormField(
                            controller: _usernameController,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('اسم المستخدم'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'اسم المستخدم مطلوب';
                              }
                              if (value.trim().length < 3) {
                                return 'اسم المستخدم قصير جداً';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // البريد الإلكترونيّ
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('البريد الإلكتروني'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'البريد الإلكتروني مطلوب';
                              }
                              if (!value.contains('@') ||
                                  !value.contains('.')) {
                                return 'بريد إلكتروني غير صالح';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // رقم الهاتف
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('رقم الهاتف'),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'رقم الهاتف مطلوب';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // كلمة المرور
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('كلمة المرور'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'كلمة المرور مطلوبة';
                              }
                              if (value.length < 8) {
                                return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // تأكيد كلمة المرور
                          TextFormField(
                            controller: _password2Controller,
                            obscureText: true,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: AppColors.onSurface),
                            decoration: _fieldDecoration('تأكيد كلمة المرور'),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'تأكيد كلمة المرور مطلوب';
                              }
                              if (value != _passwordController.text) {
                                return 'كلمتا المرور غير متطابقتين';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 8),

                          // خانة الموافقة الإلزامية مع روابط للوثائق
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                value: _acceptedTerms,
                                onChanged: (v) =>
                                    setState(() => _acceptedTerms = v ?? false),
                                activeColor: AppColors.primary,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      'أوافق على ',
                                      style: TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _legal.openPage('terms'),
                                      child: const Text(
                                        'شروط الاستخدام',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const Text(
                                      ' و',
                                      style: TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _legal.openPage('privacy'),
                                      child: const Text(
                                        'سياسة الخصوصية',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // رسالة الخطأ من الخادم
                          if (auth.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              auth.errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // زر إنشاء حساب المتدرّج
                          SizedBox(
                            height: 56,
                            child: ElevatedButton(
                              onPressed:
                                  auth.isLoading ? null : _handleRegister,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
                                  : const Text(
                                      'إنشاء حساب',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // العودة لتسجيل الدخول
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed:
                            auth.isLoading ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'سجّل دخولاً',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Text(
                        ' لديك حساب؟',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
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

  // تنسيق موحّد للحقول بزوايا 8px
  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.onSurfaceVariant),
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
    );
  }
}