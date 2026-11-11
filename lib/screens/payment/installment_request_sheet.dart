import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/installment.dart';
import '../../models/reservation.dart';
import '../../services/installment_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// طلب تقسيط يدوي عبر كي كارد: رقم الحساب، ثم «سيتم الاتصال بك».
///
/// لا شيء يُلتزم به هنا. الإدارة تتحقّق من أهلية الحساب، ثم تتصل بالمشتري
/// وتطلب منه الرمز الذي ترسله كي كارد إليه، وبعد تفعيل الخطة تعتمد الحجز
/// فيكتمل كأي حجز مدفوع. لذلك يعرض الجدول هنا تقديراً من شروط الخادم،
/// ويقول للمشتري بوضوح ما سيحدث بعد الإرسال.
///
/// تعود الورقة بالطلب عند الإرسال، أو `null` إن أُغلقت.
Future<InstallmentPlan?> showInstallmentRequestSheet(
  BuildContext context, {
  required Reservation reservation,
  required InstallmentOptions options,
  int? deliveryLocationId,
}) {
  return showModalBottomSheet<InstallmentPlan>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InstallmentRequestSheet(
      reservation: reservation,
      options: options,
      deliveryLocationId: deliveryLocationId,
    ),
  );
}

class _InstallmentRequestSheet extends StatefulWidget {
  final Reservation reservation;
  final InstallmentOptions options;
  final int? deliveryLocationId;

  const _InstallmentRequestSheet({
    required this.reservation,
    required this.options,
    this.deliveryLocationId,
  });

  @override
  State<_InstallmentRequestSheet> createState() =>
      _InstallmentRequestSheetState();
}

class _InstallmentRequestSheetState extends State<_InstallmentRequestSheet> {
  static const _minLength = 10;
  static const _maxLength = 20;

  final _controller = TextEditingController();
  final _service = InstallmentService();

  bool _sending = false;
  String? _error;
  InstallmentPlan? _sent;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _digits => _controller.text.replaceAll(' ', '');
  bool get _canSend => _digits.length >= _minLength && !_sending;

  double get _amount =>
      widget.reservation.totalPrice + widget.reservation.deliveryFee;

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final plan = await _service.request(
        reservationId: widget.reservation.id,
        accountNumber: _digits,
        deliveryLocationId: widget.deliveryLocationId,
      );
      // الرقم لا يبقى في الذاكرة بعد الإرسال.
      _controller.clear();
      if (mounted) setState(() => _sent = plan);
    } on InstallmentRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (_sent == null) ..._form() else ..._done(_sent!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _form() {
    final monthly = widget.options.monthlyFor(_amount);
    final total = widget.options.totalFor(_amount);
    return [
      Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.options.labelAr,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Text(
                  widget.reservation.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _estimate(monthly, total),
      const SizedBox(height: 16),
      TextField(
        controller: _controller,
        enabled: !_sending,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_maxLength),
          _GroupFormatter(),
        ],
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          labelText: 'رقم حساب كي كارد',
          hintText: '0000 0000 0000 0000',
          hintTextDirection: TextDirection.ltr,
          prefixIcon: const Icon(Icons.numbers_rounded),
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.surfaceContainer),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.surfaceContainer),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        _errorBox(_error!),
      ],
      const SizedBox(height: 12),
      const Text(
        'بعد الإرسال سنتصل بك لإكمال الإجراءات: ستصلك رسالة من كي كارد فيها '
        'رمز، تخبرنا به خلال المكالمة لتفعيل التقسيط. يبقى حجزك محفوظاً حتى '
        'ذلك الحين.',
        style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _canSend ? _send : null,
          style: _buttonStyle(),
          child: _sending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('إرسال طلب التقسيط',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ];
  }

  List<Widget> _done(InstallmentPlan plan) {
    return [
      const Icon(Icons.phone_in_talk_rounded,
          size: 48, color: AppColors.primary),
      const SizedBox(height: 12),
      const Text(
        'استلمنا طلبك',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        'سيتم الاتصال بك لإكمال إجراءات التقسيط. جهّز هاتفك لاستلام رمز '
        'كي كارد.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: AppColors.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(
        '${formatIqd(plan.monthlyAmount)} شهرياً × ${formatMonthsAr(plan.months)} · '
        'الحساب ****${plan.cardLast4}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 50,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context, plan),
          style: _buttonStyle(),
          child: const Text('حسناً',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    ];
  }

  /// تقدير من شروط الخادم. الرقم الكبير هو القسط لأنه القرار الفعلي، والإجمالي
  /// وفرقه عن السعر مكتوبان تحته بلا تجميل.
  Widget _estimate(double monthly, double total) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryFixed,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatIqd(monthly),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimaryFixed),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '× ${formatMonthsAr(widget.options.months)} تقريباً',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimaryFixedVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row('المبلغ (المنتج + التوصيل)', formatIqd(_amount)),
          _row('رسوم التقسيط (كي كارد والمنصة)', formatIqd(total - _amount)),
          const Divider(height: 16),
          _row('المجموع', formatIqd(total), bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 14 : 12.5,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: bold ? AppColors.onPrimaryFixed : AppColors.onPrimaryFixedVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              size: 17, color: AppColors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.surfaceContainerHigh,
        disabledForegroundColor: AppColors.outline,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );
}

/// فراغ كل أربع خانات أثناء الكتابة — رقمٌ طويل متّصل لا يُراجع بالعين.
class _GroupFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
