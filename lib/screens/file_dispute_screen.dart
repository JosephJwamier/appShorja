import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/dispute.dart';
import '../models/reservation.dart';
import '../providers/auth_provider.dart';
import '../services/dispute_service.dart';
import '../theme/app_colors.dart';

class FileDisputeScreen extends StatefulWidget {
  final Reservation reservation;
  const FileDisputeScreen({super.key, required this.reservation});

  @override
  State<FileDisputeScreen> createState() => _FileDisputeScreenState();
}

class _FileDisputeScreenState extends State<FileDisputeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'اختر سبب المشكلة أولاً');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await DisputeService().createDispute(
      accessToken: token,
      itemId: widget.reservation.item.id,
      reservationId: widget.reservation.id,
      title: 'مشكلة: ${disputeReasonLabel(_reason!)}',
      description: _descriptionController.text.trim(),
      reason: _reason!,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isEmpty
              ? 'تم إرسال النزاع — سيراجعه فريق الدعم قريباً'
              : result.message),
          backgroundColor: AppColors.success,
        ),
      );
      navigator.pop(true);
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('الإبلاغ عن مشكلة'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // بطاقة الحجز المعني
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.surfaceContainer),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: r.item.firstImage != null
                              ? AppNetworkImage(r.item.firstImage!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => _thumbFallback())
                              : _thumbFallback(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('حجز رقم #${r.id}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'ما هي المشكلة؟',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: disputeReasons.map((r) {
                    final selected = _reason == r.value;
                    return ChoiceChip(
                      label: Text(r.label),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _reason = r.value;
                        _error = null;
                      }),
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      backgroundColor: AppColors.surfaceContainerLow,
                      side: BorderSide(
                        color: selected
                            ? AppColors.primary
                            : AppColors.surfaceContainer,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                const Text(
                  'اشرح ما حدث بالتفصيل',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 5,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'مثال: استلمت المنتج بلون مختلف عن الصورة...',
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceContainer),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 10) {
                      return 'اكتب وصفاً لا يقل عن 10 أحرف';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.report_gmailerrorred_outlined),
                    label: Text(
                        _submitting ? 'جاري الإرسال...' : 'إرسال النزاع'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'سيراجع فريق الدعم النزاع ويتخذ القرار المناسب (استرجاع المبلغ أو الدفع للبائع). يمكنك متابعة الحالة من "نزاعاتي".',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.image, color: AppColors.onSurfaceVariant),
      );
}
