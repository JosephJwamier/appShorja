import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../services/item_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

class EditListingPriceScreen extends StatefulWidget {
  final Product product;

  const EditListingPriceScreen({super.key, required this.product});

  @override
  State<EditListingPriceScreen> createState() =>
      _EditListingPriceScreenState();
}

class _EditListingPriceScreenState extends State<EditListingPriceScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _originalPriceController;
  late final TextEditingController _currentPriceController;
  late bool _discountEnabled;

  bool _isSubmitting = false;
  String? _errorMessage;

  static const _inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final currentPrice = p.price ?? 0;
    _discountEnabled = (p.originalPrice ?? 0) > currentPrice;
    final basePrice = _discountEnabled ? p.originalPrice! : currentPrice;
    _originalPriceController = TextEditingController(
      text: basePrice > 0 ? basePrice.toStringAsFixed(0) : '',
    );
    _currentPriceController = TextEditingController(
      text: _discountEnabled ? currentPrice.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _originalPriceController.dispose();
    _currentPriceController.dispose();
    super.dispose();
  }

  double? get _originalPrice =>
      double.tryParse(_originalPriceController.text.trim());
  double? get _currentPrice =>
      double.tryParse(_currentPriceController.text.trim());

  int? get _discountPct {
    final original = _originalPrice;
    final current = _currentPrice;
    if (!_discountEnabled || original == null || current == null) return null;
    if (original <= current || original <= 0) return null;
    return ((1 - current / original) * 100).round();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final effectivePrice = _discountEnabled ? _currentPrice! : _originalPrice!;
      await ItemService().updateFixedListing(
        accessToken: auth.accessToken!,
        itemId: widget.product.id,
        price: effectivePrice,
        originalPrice: _discountEnabled ? _originalPrice : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _discountEnabled ? 'تم تفعيل الخصم بنجاح' : 'تم تحديث السعر',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context, true);
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
        appBar: AppBar(title: const Text('السعر والخصم')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroBanner(itemTitle: widget.product.title),
                  const SizedBox(height: 24),

                  const _SectionTitle(
                    title: 'السعر الأصلي',
                    icon: Icons.sell_outlined,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _originalPriceController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'السعر (IQD)',
                      helperText: 'هذا هو سعر المنتج الأساسي قبل أي خصم',
                      border: _inputBorder,
                    ),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) return 'أدخل سعراً صحيحاً';
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionTitle(
                          title: 'تفعيل خصم',
                          icon: Icons.discount_outlined,
                        ),
                      ),
                      Switch(
                        value: _discountEnabled,
                        onChanged: (v) => setState(() {
                          _discountEnabled = v;
                          if (!v) _currentPriceController.clear();
                        }),
                      ),
                    ],
                  ),
                  if (_discountEnabled) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _currentPriceController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'السعر الحالي بعد الخصم (IQD)',
                        helperText: 'هذا هو السعر الذي يدفعه المشتري فعليًا',
                        prefixIcon: Icon(Icons.price_change_outlined),
                        border: _inputBorder,
                      ),
                      validator: (v) {
                        if (!_discountEnabled) return null;
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return 'أدخل سعراً صحيحاً';
                        final original = _originalPrice;
                        if (original != null && n >= original) {
                          return 'يجب أن يكون أقل من السعر الأصلي';
                        }
                        return null;
                      },
                    ),
                    if (_discountPct != null) ...[
                      const SizedBox(height: 16),
                      _DiscountPreviewCard(
                        pct: _discountPct!,
                        price: _currentPrice!,
                        originalPrice: _originalPrice!,
                      ),
                    ],
                  ],

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
            Icons.local_offer_outlined,
            color: AppColors.tertiary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
              children: [
                const TextSpan(text: 'تعديل سعر '),
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
// Discount preview
// ─────────────────────────────────────────────────────────────────────────────

class _DiscountPreviewCard extends StatelessWidget {
  final int pct;
  final double price;
  final double originalPrice;

  const _DiscountPreviewCard({
    required this.pct,
    required this.price,
    required this.originalPrice,
  });

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
      border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
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
            Icons.discount_outlined,
            color: AppColors.secondary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيظهر للمشترين خصم $pct٪',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatNum(originalPrice)} IQD  ←  ${formatNum(price)} IQD',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.onSurface,
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
            : const Icon(Icons.check),
        label: Text(isSubmitting ? 'جاري الحفظ...' : 'حفظ'),
      ),
    ),
  );
}
