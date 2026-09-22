import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/transfers_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

class ResaleRequestScreen extends StatefulWidget {
  final int itemId;
  final String itemTitle;
  final double? unitPrice;
  final int maxQuantity;

  const ResaleRequestScreen({
    super.key,
    required this.itemId,
    required this.itemTitle,
    this.unitPrice,
    required this.maxQuantity,
  });

  @override
  State<ResaleRequestScreen> createState() => _ResaleRequestScreenState();
}

class _ResaleRequestScreenState extends State<ResaleRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _durationController = TextEditingController(text: '30');
  final _storageFeeAmountController = TextEditingController();
  final _storageFeePeriodController = TextEditingController(text: '30');
  final _messageController = TextEditingController();
  final _notesController = TextEditingController();

  String _storageFeeType = 'none';
  int _quantity = 1;

  bool _isSubmitting = false;
  String? _errorMessage;

  static const _inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  double get _totalWholesalePrice => (widget.unitPrice ?? 0) * _quantity;

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(() {
      final n = int.tryParse(_quantityController.text.trim());
      if (n != null && n != _quantity) setState(() => _quantity = n);
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _durationController.dispose();
    _storageFeeAmountController.dispose();
    _storageFeePeriodController.dispose();
    _messageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _setQuantity(int value) {
    final clamped = value.clamp(1, widget.maxQuantity == 0 ? 1 : widget.maxQuantity);
    _quantityController.text = '$clamped';
    setState(() => _quantity = clamped);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final provider = Provider.of<TransfersProvider>(context, listen: false);

      final durationText = _durationController.text.trim();

      final result = await provider.createAgreement(
        token: auth.accessToken!,
        itemId: widget.itemId,
        quantity: int.parse(_quantityController.text.trim()),
        storageFeeType: _storageFeeType,
        storageFeeAmount: _storageFeeType == 'none'
            ? null
            : double.tryParse(_storageFeeAmountController.text),
        storageFeePeriodDays:
            int.tryParse(_storageFeePeriodController.text.trim()) ?? 30,
        durationDays: durationText.isEmpty ? null : int.parse(durationText),
        requestMessage: _messageController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      if (result.success) {
        // أول طلب إعادة بيع/نقل ملكية ناجح هو أول لحظة يصبح فيها إشعار الرد
        // مفيدًا فعليًا — نطلب إذن الإشعارات هنا بدل أول فتحة للتطبيق.
        NotificationService.requestPermissionIfNeeded();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() => _errorMessage = result.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلب نقل ملكية بالجملة')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroBanner(itemTitle: widget.itemTitle),
                  const SizedBox(height: 24),

                  const _SectionTitle(
                    title: 'الكمية المطلوبة',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 10),
                  _QuantityField(
                    controller: _quantityController,
                    max: widget.maxQuantity,
                    onChanged: _setQuantity,
                  ),
                  const SizedBox(height: 8),
                  _AvailabilityPill(max: widget.maxQuantity),

                  if (widget.unitPrice != null) ...[
                    const SizedBox(height: 16),
                    _WalletPreviewCard(amount: _totalWholesalePrice),
                  ],

                  const SizedBox(height: 24),
                  const _SectionTitle(
                    title: 'مدّة الاستضافة',
                    icon: Icons.warehouse_outlined,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد الأيّام (اختياري)',
                      helperText:
                          'الفترة التي تبقى فيها البضاعة في مخزن المالك',
                      border: _inputBorder,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = int.tryParse(v);
                      if (n == null || n < 1 || n > 730) {
                        return 'المدّة بين 1 و 730 يوماً';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(
                    title: 'رسوم التخزين',
                    icon: Icons.local_shipping_outlined,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      selectedForegroundColor: AppColors.primary,
                    ),
                    segments: const [
                      ButtonSegment(value: 'none', label: Text('بدون')),
                      ButtonSegment(value: 'flat_rate', label: Text('مبلغ ثابت')),
                      ButtonSegment(value: 'percentage', label: Text('نسبة')),
                    ],
                    selected: {_storageFeeType},
                    onSelectionChanged: (s) =>
                        setState(() => _storageFeeType = s.first),
                  ),
                  if (_storageFeeType != 'none') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.surfaceContainer),
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _storageFeeAmountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _storageFeeType == 'percentage'
                                  ? 'نسبة رسوم التخزين (٪)'
                                  : 'قيمة رسوم التخزين (IQD)',
                              prefixIcon: Icon(
                                _storageFeeType == 'percentage'
                                    ? Icons.percent
                                    : Icons.payments_outlined,
                              ),
                              border: _inputBorder,
                            ),
                            validator: (v) {
                              if (_storageFeeType == 'none') return null;
                              if (v == null || v.trim().isEmpty) {
                                return 'قيمة الرسوم مطلوبة';
                              }
                              final n = double.tryParse(v);
                              if (n == null || n <= 0) return 'أدخل قيمة صحيحة';
                              if (_storageFeeType == 'percentage' && n > 100) {
                                return 'النسبة بين 0 و 100';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _storageFeePeriodController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'مدّة التكرار (بالأيّام)',
                              helperText: 'كل كم يوم تُستحق رسوم التخزين',
                              prefixIcon: Icon(Icons.event_repeat_outlined),
                              border: _inputBorder,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return null;
                              final n = int.tryParse(v);
                              if (n == null || n <= 0) {
                                return 'أدخل عدد أيّام صحيح';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const _SectionTitle(
                    title: 'تفاصيل إضافية',
                    icon: Icons.notes_outlined,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'رسالة للمالك (اختياري)',
                      hintText: 'اشرح لماذا تريد هذه الكمية...',
                      border: _inputBorder,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      hintText: 'ملاحظات إضافية خاصة بالاتفاقية...',
                      border: _inputBorder,
                      alignLabelWithHint: true,
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 20),
                    _ErrorBanner(message: _errorMessage!),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: _SubmitBar(
          isSubmitting: _isSubmitting,
          onSubmit: _submit,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero banner
// ─────────────────────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  final String itemTitle;
  const _HeroBanner({required this.itemTitle});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          AppColors.tertiaryFixed.withValues(alpha: 0.55),
          AppColors.surfaceContainerLowest,
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.tertiaryContainer.withValues(alpha: 0.45),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.tertiaryContainer.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.storefront_outlined,
            color: AppColors.tertiary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.onSurface,
              ),
              children: [
                const TextSpan(text: 'تطلب نقل ملكية كمية من '),
                TextSpan(
                  text: '"$itemTitle"',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section title
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Icon(icon, size: 17, color: AppColors.onSurfaceVariant),
      const SizedBox(width: 6),
      Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity field (stepper + editable number)
// ─────────────────────────────────────────────────────────────────────────────

class _QuantityField extends StatelessWidget {
  final TextEditingController controller;
  final int max;
  final ValueChanged<int> onChanged;

  const _QuantityField({
    required this.controller,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = int.tryParse(controller.text) ?? 1;
    return FormField<int>(
      initialValue: current,
      validator: (_) {
        final n = int.tryParse(controller.text.trim());
        if (n == null || n < 1) return 'أدخل كمية صحيحة';
        if (max > 0 && n > max) return 'الكمية أكبر من المتوفر ($max)';
        return null;
      },
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: field.hasError
                    ? AppColors.error
                    : AppColors.surfaceContainer,
              ),
            ),
            child: Row(
              children: [
                _stepBtn(
                  Icons.remove_rounded,
                  current > 1
                      ? () {
                          onChanged(current - 1);
                          field.didChange(current - 1);
                        }
                      : null,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (v) => field.didChange(int.tryParse(v)),
                  ),
                ),
                _stepBtn(
                  Icons.add_rounded,
                  max <= 0 || current < max
                      ? () {
                          onChanged(current + 1);
                          field.didChange(current + 1);
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (field.hasError) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                field.errorText!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 52,
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? AppColors.primary
              : AppColors.outline.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  final int max;
  const _AvailabilityPill({required this.max});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inventory_outlined,
            size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          'المتوفّر على المنتج: $max قطعة',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Wallet deduction preview
// ─────────────────────────────────────────────────────────────────────────────

class _WalletPreviewCard extends StatelessWidget {
  final double amount;
  const _WalletPreviewCard({required this.amount});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [
          AppColors.secondaryFixed.withValues(alpha: 0.55),
          AppColors.surfaceContainerLowest,
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.secondary.withValues(alpha: 0.35),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.account_balance_wallet_outlined,
            color: AppColors.secondary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'سيُخصم من محفظتك عند موافقة المالك',
                style: TextStyle(fontSize: 12.5, color: AppColors.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                formatIqd(amount),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Error banner
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.errorContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 18, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.onErrorContainer),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky submit bar
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  final bool isSubmitting;
  final VoidCallback onSubmit;
  const _SubmitBar({required this.isSubmitting, required this.onSubmit});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      MediaQuery.of(context).padding.bottom + 12,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: const Border(top: BorderSide(color: AppColors.surfaceContainer)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: isSubmitting ? null : onSubmit,
        icon: isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.send),
        label: Text(isSubmitting ? 'جاري الإرسال...' : 'إرسال الطلب'),
      ),
    ),
  );
}
