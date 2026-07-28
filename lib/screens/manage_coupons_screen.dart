import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/store_coupon.dart';
import '../providers/auth_provider.dart';
import '../services/store_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _formatDate(DateTime dt) => '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

class ManageCouponsScreen extends StatefulWidget {
  final int storeId;
  const ManageCouponsScreen({super.key, required this.storeId});

  @override
  State<ManageCouponsScreen> createState() => _ManageCouponsScreenState();
}

class _ManageCouponsScreenState extends State<ManageCouponsScreen> {
  final _service = StoreService();
  List<StoreCoupon> _coupons = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final coupons = await _service.fetchStoreCoupons(
        accessToken: token,
        storeId: widget.storeId,
      );
      if (mounted) {
        setState(() {
          _coupons = coupons;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _openForm({StoreCoupon? coupon}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CouponFormSheet(storeId: widget.storeId, coupon: coupon),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(StoreCoupon coupon) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الكوبون'),
        content: Text('هل تريد حذف الكوبون "${coupon.code}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await _service.deleteCoupon(
      accessToken: token,
      storeId: widget.storeId,
      couponId: coupon.id,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message.isEmpty
            ? (result.success ? 'تم حذف الكوبون' : 'تعذّر الحذف')
            : result.message),
      ),
    );
    if (result.success) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('إدارة الكوبونات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('كوبون جديد'),
        backgroundColor: AppColors.primary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    if (_coupons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.confirmation_number_outlined,
                  size: 64, color: AppColors.outline),
              const SizedBox(height: 12),
              const Text('لا توجد كوبونات بعد',
                  style: TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 15)),
              const SizedBox(height: 8),
              const Text(
                'أضف كوبوناً ليجمعه الزبائن ويحصلوا على خصم في متجرك',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: _coupons.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _couponTile(_coupons[i]),
      ),
    );
  }

  Widget _couponTile(StoreCoupon c) {
    final expired = c.expiresAt != null && c.expiresAt!.isBefore(DateTime.now());
    final statusLabel = !c.isActive ? 'موقوف' : (expired ? 'منتهي' : 'نشط');
    final statusColor = !c.isActive
        ? AppColors.onSurfaceVariant
        : (expired ? AppColors.error : AppColors.primary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor),
                ),
              ),
              const Spacer(),
              Text(
                formatIqd(c.amount),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'كود: ${c.code}',
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface),
          ),
          if (c.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              c.description,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            c.minOrderAmount > 0
                ? 'للطلبات فوق ${formatIqd(c.minOrderAmount)}'
                : 'بدون حد أدنى للطلب',
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          if (c.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'ينتهي في: ${_formatDate(c.expiresAt!)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
          Divider(
              height: 24, color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _delete(c),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                label: const Text('حذف',
                    style: TextStyle(color: AppColors.error)),
              ),
              TextButton.icon(
                onPressed: () => _openForm(coupon: c),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('تعديل'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CouponFormSheet extends StatefulWidget {
  final int storeId;
  final StoreCoupon? coupon;
  const _CouponFormSheet({required this.storeId, this.coupon});

  @override
  State<_CouponFormSheet> createState() => _CouponFormSheetState();
}

class _CouponFormSheetState extends State<_CouponFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _amountController;
  late final TextEditingController _minOrderController;
  late final TextEditingController _descriptionController;
  bool _isActive = true;
  DateTime? _expiresAt;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.coupon != null;

  @override
  void initState() {
    super.initState();
    final c = widget.coupon;
    _codeController = TextEditingController(text: c?.code ?? '');
    _amountController =
        TextEditingController(text: c != null ? _trimZeros(c.amount) : '');
    _minOrderController = TextEditingController(
        text: c != null ? _trimZeros(c.minOrderAmount) : '0');
    _descriptionController = TextEditingController(text: c?.description ?? '');
    _isActive = c?.isActive ?? true;
    _expiresAt = c?.expiresAt;
  }

  String _trimZeros(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _amountController.dispose();
    _minOrderController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null) return;
    setState(() =>
        _expiresAt = DateTime(date.year, date.month, date.day, 23, 59, 59));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final minOrder = double.tryParse(_minOrderController.text.trim()) ?? 0;
    final service = StoreService();

    final result = _isEditing
        ? await service.updateCoupon(
            accessToken: token,
            storeId: widget.storeId,
            couponId: widget.coupon!.id,
            code: _codeController.text.trim(),
            amount: amount,
            minOrderAmount: minOrder,
            description: _descriptionController.text.trim(),
            isActive: _isActive,
            expiresAt: _expiresAt,
            clearExpiresAt: _expiresAt == null,
          )
        : await service.createCoupon(
            accessToken: token,
            storeId: widget.storeId,
            code: _codeController.text.trim(),
            amount: amount,
            minOrderAmount: minOrder,
            description: _descriptionController.text.trim(),
            isActive: _isActive,
            expiresAt: _expiresAt,
          );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEditing ? 'تعديل الكوبون' : 'كوبون جديد',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _codeController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'كود الكوبون',
                  hintText: 'مثال: SAVE10',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'كود الكوبون مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'قيمة الخصم (د.ع)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'أدخل قيمة خصم صحيحة';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minOrderController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الحد الأدنى للطلب (اختياري)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v.trim());
                  if (n == null || n < 0) return 'قيمة غير صالحة';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                textAlign: TextAlign.right,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'وصف (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickExpiry,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined,
                          color: _expiresAt != null
                              ? AppColors.primary
                              : Colors.grey,
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _expiresAt != null
                              ? 'ينتهي في ${_formatDate(_expiresAt!)}'
                              : 'بدون تاريخ انتهاء (اضغط للتحديد)',
                          style: TextStyle(
                            color: _expiresAt != null
                                ? AppColors.onSurface
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_expiresAt != null)
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: AppColors.error),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _expiresAt = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('الكوبون نشط'),
                subtitle: Text(_isActive
                    ? 'يمكن للزبائن جمعه الآن'
                    : 'مخفي عن الزبائن'),
                activeThumbColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving
                      ? 'جاري الحفظ...'
                      : (_isEditing ? 'حفظ التغييرات' : 'إنشاء الكوبون')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
