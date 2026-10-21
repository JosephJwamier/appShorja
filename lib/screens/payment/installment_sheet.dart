import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/installment.dart';
import '../../models/reservation.dart';
import '../../services/installment_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// شراء بالتقسيط: رقم البطاقة، ثم الجدول، ثم التأكيد.
///
/// خطوتان لا واحدة عن قصد. الفحص يُظهر للمشتري ما سيلتزم به فعلاً — قسط
/// شهري وعدد أشهر وإجمالي يزيد على السعر — **قبل** أن يُنشأ أي التزام عند
/// المموّل. فمن يرى «١١٠ آلاف × ١٠ أشهر» ويتراجع لم يخسر شيئاً، ومن يرى
/// الرقم بعد التأكيد يكون قد وقّع على عشرة أشهر استقطاع من راتبه بلا أن
/// يسأله أحد.
///
/// رقم البطاقة لا يُخزَّن ولا يُسجَّل: يُرسل في نداء الفحص ويعود منه مرجع
/// عرض، والتأكيد يحمل المرجع وحده (انظر [InstallmentService]).
Future<InstallmentPlan?> showInstallmentSheet(
  BuildContext context, {
  required Reservation reservation,
  required InstallmentOptions options,
  int? deliveryLocationId,
}) {
  return showModalBottomSheet<InstallmentPlan>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (_) => _InstallmentSheet(
      reservation: reservation,
      options: options,
      deliveryLocationId: deliveryLocationId,
    ),
  );
}

class _InstallmentSheet extends StatefulWidget {
  final Reservation reservation;
  final InstallmentOptions options;
  final int? deliveryLocationId;

  const _InstallmentSheet({
    required this.reservation,
    required this.options,
    this.deliveryLocationId,
  });

  @override
  State<_InstallmentSheet> createState() => _InstallmentSheetState();
}

class _InstallmentSheetState extends State<_InstallmentSheet> {
  final _controller = TextEditingController();
  final _service = InstallmentService();

  InstallmentPlan? _quote;
  bool _checking = false;
  bool _confirming = false;
  String? _refusal;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _digits => _controller.text.replaceAll(' ', '');
  bool get _canCheck => _digits.length >= 16 && !_checking && !_confirming;

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _refusal = null;
      _quote = null;
    });
    try {
      final plan = await _service.check(
        reservationId: widget.reservation.id,
        cardNumber: _digits,
        deliveryLocationId: widget.deliveryLocationId,
      );
      if (mounted) setState(() => _quote = plan);
    } on InstallmentRefused catch (e) {
      if (mounted) setState(() => _refusal = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _refusal = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _confirm() async {
    final quote = _quote;
    if (quote == null) return;
    setState(() {
      _confirming = true;
      _refusal = null;
    });
    try {
      final plan = await _service.confirm(reference: quote.reference);
      if (mounted) Navigator.pop(context, plan);
    } on InstallmentRefused catch (e) {
      if (!mounted) return;
      // عرضٌ انتهى: الطريق معروف — يُعاد الفحص، لا تُعرض رسالة خطأ
      // وتُترك البطاقة كما هي.
      setState(() {
        _confirming = false;
        _refusal = e.message;
        if (e.isStaleQuote) _quote = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _refusal = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
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
                Row(
                  children: [
                    const Icon(Icons.credit_card_rounded,
                        color: AppColors.primary),
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
                                fontSize: 12.5,
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _cardField(),
                const SizedBox(height: 10),
                if (quote == null) _estimateLine(),
                if (_refusal != null) ...[
                  const SizedBox(height: 10),
                  _refusalBox(_refusal!),
                ],
                if (quote != null) ...[
                  const SizedBox(height: 14),
                  _schedule(quote),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: quote == null
                      ? ElevatedButton(
                          onPressed: _canCheck ? _check : null,
                          style: _buttonStyle(),
                          child: _checking
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('تحقّق من الأهلية',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        )
                      : ElevatedButton(
                          onPressed: _confirming ? null : _confirm,
                          style: _buttonStyle(),
                          child: _confirming
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  'أكّد الشراء — ${formatIqd(quote.monthlyAmount)} شهرياً',
                                  style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.bold)),
                        ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'لا نحفظ رقم بطاقتك — يُستخدم للتحقّق مع كي كارد فقط، '
                  'ويبقى عندنا آخر أربعة أرقام.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
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

  Widget _cardField() {
    return TextField(
      controller: _controller,
      enabled: !_confirming,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      // يُجمَّع كل أربع خانات أثناء الكتابة: رقم من ستة عشر رقماً متّصلاً
      // لا يُراجع بالعين، وأكثر أخطاء التقسيط رقمٌ واحد مقلوب.
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(16),
        _CardGroupFormatter(),
      ],
      onChanged: (_) {
        if (_quote != null || _refusal != null) {
          setState(() {
            _quote = null;
            _refusal = null;
          });
        }
      },
      decoration: InputDecoration(
        labelText: 'رقم بطاقة كي كارد',
        hintText: '0000 0000 0000 0000',
        hintTextDirection: TextDirection.ltr,
        prefixIcon: const Icon(Icons.credit_card_outlined),
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
    );
  }

  /// تقدير قبل الفحص، من شروط الخادم — ليعرف المشتري حجم القسط قبل أن
  /// يُخرج بطاقته من جيبه.
  Widget _estimateLine() {
    final amount = widget.reservation.totalPrice + widget.reservation.deliveryFee;
    final monthly = widget.options.monthlyFor(amount);
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 15,
            color: AppColors.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'تقديراً: ${formatIqd(monthly)} شهرياً لمدة '
            '${widget.options.months} أشهر',
            style: const TextStyle(
                fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _refusalBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 17,
              color: AppColors.onErrorContainer),
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

  /// الجدول الذي يوافق عليه المشتري. الرقم الكبير هو القسط الشهري لأنه
  /// القرار الفعلي؛ والإجمالي وفرقه عن السعر مكتوبان تحته بلا تجميل —
  /// تقسيطٌ يخفي كلفته ليس عرضاً، إنه فاتورة مؤجّلة.
  Widget _schedule(InstallmentPlan quote) {
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
                formatIqd(quote.monthlyAmount),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimaryFixed),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '× ${quote.months} أشهر',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onPrimaryFixedVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row('سعر المنتج', formatIqd(quote.principal)),
          _row('إضافة كي كارد للتقسيط', formatIqd(quote.customerFeeAmount)),
          const Divider(height: 16),
          _row('المجموع على عشرة أشهر', formatIqd(quote.totalPayable),
              bold: true),
          if (quote.cardHolderName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${quote.cardHolderName} — بطاقة ****${quote.cardLast4}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onPrimaryFixedVariant),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'يُستقطع القسط من بطاقتك شهرياً. ومبلغ الشراء يبقى محفوظاً لدينا '
            'ولا يصل البائع إلا بعد تأكيدك استلام المنتج.',
            style: TextStyle(
                fontSize: 11.5, color: AppColors.onPrimaryFixedVariant),
          ),
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
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// يُدخل فراغاً كل أربع خانات أثناء الكتابة، ويُبقي المؤشّر في موضعه
/// المنطقي بعد الإدخال.
class _CardGroupFormatter extends TextInputFormatter {
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
