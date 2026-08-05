import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../services/report_service.dart';
import '../theme/app_colors.dart';

/// Opens the "report" bottom sheet for an item, a store, or a user.
/// [targetLabel] is shown under the title (e.g. the item's title or the
/// store's name) so the reporter can confirm what they're about to report.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required int targetId,
  required String targetLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReportBottomSheet(
      targetType: targetType,
      targetId: targetId,
      targetLabel: targetLabel,
    ),
  );
}

class ReportBottomSheet extends StatefulWidget {
  final String targetType;
  final int targetId;
  final String targetLabel;

  const ReportBottomSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
  });

  @override
  State<ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<ReportBottomSheet> {
  final _descriptionController = TextEditingController();
  String? _reason;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.targetType) {
      case 'item':
        return 'الإبلاغ عن المنتج';
      case 'store':
        return 'الإبلاغ عن المتجر';
      default:
        return 'الإبلاغ عن المستخدم';
    }
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = 'اختر سبب البلاغ أولاً');
      return;
    }
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ReportService().createReport(
      accessToken: token,
      targetType: widget.targetType,
      targetId: widget.targetId,
      reason: _reason!,
      description: _descriptionController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message.isEmpty
              ? 'تم إرسال بلاغك، شكراً لمساعدتك في الحفاظ على أمان المنصة'
              : result.message),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      setState(() => _error = result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = reportReasonsFor(widget.targetType);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // مقبض السحب
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // العنوان + شارة أيقونة + إغلاق
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.flag_rounded,
                        color: AppColors.error, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          widget.targetLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          color: AppColors.onSurfaceVariant, size: 22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('ما سبب البلاغ؟',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons.map((r) {
                  final selected = _reason == r.value;
                  return ChoiceChip(
                    label: Text(r.label),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _reason = r.value;
                      _error = null;
                    }),
                    selectedColor: AppColors.error,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    backgroundColor: AppColors.surfaceContainerLow,
                    side: BorderSide(
                      color:
                          selected ? AppColors.error : AppColors.surfaceContainer,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              const Text('تفاصيل إضافية (اختياري)',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                maxLength: 500,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'اكتب أي تفاصيل تساعدنا على مراجعة البلاغ...',
                  hintTextDirection: TextDirection.rtl,
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.surfaceContainer),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.surfaceContainer),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.error, width: 2),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
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
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_submitting ? 'جاري الإرسال...' : 'إرسال البلاغ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'بلاغك سرّي تماماً — لن يتم إشعار الطرف الذي تُبلغ عنه بهويتك.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
