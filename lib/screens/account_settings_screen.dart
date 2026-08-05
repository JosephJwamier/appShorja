import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../services/auth_service.dart';
import '../services/legal_service.dart';
import '../theme/app_colors.dart';
import 'change_password_screen.dart';
import 'verify_code_sheet.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _service = AuthService();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _bioController;
  DateTime? _dateOfBirth;
  XFile? _avatarFile;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _dateOfBirth = user?.dateOfBirth;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _avatarFile = picked);
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 13, now.month, now.day),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    final user = auth.user;
    if (token == null || user == null) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final bio = _bioController.text.trim();

    if (firstName == user.firstName &&
        lastName == user.lastName &&
        username == user.username &&
        email == user.email &&
        phone == user.phone &&
        bio == user.bio &&
        _dateOfBirth == user.dateOfBirth &&
        _avatarFile == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await _service.updateProfile(
      accessToken: token,
      username: username != user.username ? username : null,
      firstName: firstName != user.firstName ? firstName : null,
      lastName: lastName != user.lastName ? lastName : null,
      email: email != user.email ? email : null,
      phone: phone != user.phone ? phone : null,
      bio: bio != user.bio ? bio : null,
      dateOfBirth: _dateOfBirth != user.dateOfBirth ? _dateOfBirth : null,
      avatar: _avatarFile,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result.success) _avatarFile = null;
    });

    if (!result.success) {
      setState(() => _error = result.message);
      return;
    }

    await auth.updateUser(result.user!);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
          content: Text('تم حفظ التغييرات'), backgroundColor: AppColors.success),
    );
  }

  Future<void> _verifyEmail() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    final verified = await showVerifyCodeSheet(
      context,
      title: 'تفعيل البريد الإلكتروني',
      subtitle: 'أرسلنا رمزاً مكوّناً من 6 أرقام إلى بريدك الإلكتروني',
      onSendCode: () => _service.sendEmailVerificationCode(accessToken: token),
      onVerifyCode: (code) =>
          _service.verifyEmailCode(accessToken: token, code: code),
    );
    if (verified == true && mounted) {
      await auth.updateUser(auth.user!.copyWith(emailVerified: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم تفعيل بريدك الإلكتروني'),
              backgroundColor: AppColors.success),
        );
      }
    }
  }

  Future<void> _verifyPhone() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    if ((auth.user?.phone ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف رقم هاتف أولاً ثم احفظ التغييرات')),
      );
      return;
    }
    final verified = await showVerifyCodeSheet(
      context,
      title: 'تفعيل رقم الهاتف',
      subtitle: 'أرسلنا رمزاً مكوّناً من 6 أرقام برسالة نصية',
      onSendCode: () => _service.sendPhoneVerificationCode(accessToken: token),
      onVerifyCode: (code) =>
          _service.verifyPhoneCode(accessToken: token, code: code),
    );
    if (verified == true && mounted) {
      await auth.updateUser(auth.user!.copyWith(phoneVerified: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم تفعيل رقم هاتفك'),
              backgroundColor: AppColors.success),
        );
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الحساب نهائيًا؟'),
          content: const Text(
            'لا يمكن التراجع عن هذا الإجراء. سيتم تعطيل حسابك فورًا وحذف بياناتك '
            'الشخصية. إن كان لديك رصيد في المحفظة أو حجوزات أو نزاعات قيد التنفيذ، '
            'يجب تسويتها أولًا وستظهر لك رسالة توضّح ذلك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('حذف الحساب'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final auth = context.read<AuthProvider>();
    final notificationsProvider = context.read<NotificationsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _deleting = true);
    final failureMessage = await auth.deleteAccount(
      notificationsProvider: notificationsProvider,
    );
    if (!mounted) return;
    setState(() => _deleting = false);

    if (failureMessage != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage), backgroundColor: AppColors.error),
      );
      return;
    }
    // On success AuthProvider clears the session and notifies listeners —
    // AuthGate (main.dart) reacts by swapping straight to LoginScreen, which
    // unmounts this whole authenticated subtree, so no navigation is needed here.
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('إعدادات الحساب'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: AppColors.primaryContainer,
                        backgroundImage: _avatarFile != null
                            ? NetworkImage(_avatarFile!.path)
                            : (user?.fullAvatarUrl != null
                                ? CachedNetworkImageProvider(user!.fullAvatarUrl!)
                                : null),
                        child: (_avatarFile == null && user?.fullAvatarUrl == null)
                            ? Text(
                                (user?.displayName ?? '?').characters.first.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_outlined,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('الاسم الأول'),
              const SizedBox(height: 8),
              TextField(
                controller: _firstNameController,
                textAlign: TextAlign.right,
                decoration: _fieldDecoration(),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('الاسم الثاني'),
              const SizedBox(height: 8),
              TextField(
                controller: _lastNameController,
                textAlign: TextAlign.right,
                decoration: _fieldDecoration(),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('اسم المستخدم'),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                textAlign: TextAlign.right,
                decoration: _fieldDecoration(),
              ),
              const SizedBox(height: 20),
              const _SectionLabel('البريد الإلكتروني'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.emailAddress,
                decoration: _fieldDecoration(),
              ),
              const SizedBox(height: 8),
              _VerificationRow(
                verified: user?.emailVerified ?? false,
                verifiedLabel: 'البريد مفعَّل',
                actionLabel: 'تفعيل البريد',
                onVerify: _verifyEmail,
              ),
              const SizedBox(height: 20),
              const _SectionLabel('رقم الهاتف'),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.phone,
                decoration: _fieldDecoration(),
              ),
              const SizedBox(height: 8),
              _VerificationRow(
                verified: user?.phoneVerified ?? false,
                verifiedLabel: 'الهاتف مفعَّل',
                actionLabel: 'تفعيل الهاتف',
                onVerify: _verifyPhone,
              ),
              const SizedBox(height: 20),
              const _SectionLabel('نبذة تعريفية'),
              const SizedBox(height: 8),
              TextField(
                controller: _bioController,
                textAlign: TextAlign.right,
                maxLength: 500,
                maxLines: 3,
                decoration: _fieldDecoration(),
              ),
              const SizedBox(height: 12),
              const _SectionLabel('تاريخ الميلاد'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDateOfBirth,
                child: InputDecorator(
                  decoration: _fieldDecoration(),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _dateOfBirth != null
                          ? '${_dateOfBirth!.year}/${_dateOfBirth!.month}/${_dateOfBirth!.day}'
                          : 'غير محدد',
                      style: TextStyle(
                        color: _dateOfBirth != null
                            ? AppColors.onSurface
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التغييرات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Divider(height: 1),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline, color: AppColors.primary),
                title: const Text('تغيير كلمة المرور'),
                trailing: const Icon(Icons.chevron_left, color: AppColors.onSurfaceVariant),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // سياسة الخصوصية
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined,
                    color: AppColors.primary),
                title: const Text('سياسة الخصوصية'),
                trailing: const Icon(Icons.open_in_new,
                    size: 18, color: AppColors.onSurfaceVariant),
                onTap: () => LegalService().openPage('privacy'),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // شروط الاستخدام
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined,
                    color: AppColors.primary),
                title: const Text('شروط الاستخدام'),
                trailing: const Icon(Icons.open_in_new,
                    size: 18, color: AppColors.onSurfaceVariant),
                onTap: () => LegalService().openPage('terms'),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _deleting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.error),
                      )
                    : const Icon(Icons.delete_forever_outlined, color: AppColors.error),
                title: const Text('حذف الحساب',
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                onTap: _deleting ? null : _confirmDeleteAccount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration() => InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.surfaceContainer),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant)),
    );
  }
}

class _VerificationRow extends StatelessWidget {
  final bool verified;
  final String verifiedLabel;
  final String actionLabel;
  final VoidCallback onVerify;

  const _VerificationRow({
    required this.verified,
    required this.verifiedLabel,
    required this.actionLabel,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    if (verified) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(verifiedLabel,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success)),
          const SizedBox(width: 6),
          const Icon(Icons.check_circle, size: 16, color: AppColors.success),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: onVerify,
          icon: const Icon(Icons.verified_outlined, size: 16),
          label: Text(actionLabel),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.tertiary,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
