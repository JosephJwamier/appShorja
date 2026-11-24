import 'package:flutter/services.dart';

/// كل ما يخصّ إدخال مبلغ بالدينار: الفواصل أثناء الكتابة
/// ([AmountInputFormatter])، وتعبئة الحقل ([amountText])، وقراءته
/// ([parseAmount]).
///
/// الثلاثة معاً: `double.tryParse('1,000')` يعيد null، فحقلٌ يُنسَّق ولا
/// يُقرأ بـ[parseAmount] يرفض كل مبلغ فوق 999.

/// أطول مبلغ يُقبل (خانات). أعمدة المبالغ في الخادم max_digits=12 منها
/// خانتان عشريتان.
const _maxDigits = 10;

/// الأرقام العربية والفارسية إلى لاتينية — لوحة المفاتيح العربية تكتبها.
String _latinDigits(String s) => s.replaceAllMapped(
      RegExp('[٠-٩۰-۹]'),
      (m) {
        final c = m[0]!.codeUnitAt(0);
        return '${c - (c >= 0x06F0 ? 0x06F0 : 0x0660)}';
      },
    );

String _group(String digits) => digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+$)'),
      (_) => ',',
    );

/// نصّ الحقل لمبلغ معروف: 25000 -> "25,000". فارغ لـ null.
String amountText(num? amount) =>
    amount == null ? '' : _group(amount.round().abs().toString());

/// المبلغ المكتوب في الحقل، أو null إن كان فارغاً أو غير صالح.
double? parseAmount(String? text) {
  final plain =
      _latinDigits(text ?? '').replaceAll(RegExp('[,٬،\\s]'), '');
  return double.tryParse(plain);
}

/// فواصل الآلاف أثناء الكتابة: 1000000 -> 1,000,000.
///
/// أرقام فقط — لا كسور في الدينار. والنقطة تُسقَط عمداً: من يكتب "25.000"
/// يقصد 25 ألفاً، وقراءتها عشريةً تجعلها 25 ديناراً.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  static String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = _latinDigits(newValue.text);
    var caret = newValue.selection.end;
    if (caret < 0 || caret > text.length) caret = text.length;

    // لصق "25000.00" ليس مليونين ونصفاً: الكسر الملصوق يُحذف.
    if (text.length - oldValue.text.length > 1) {
      text = text.replaceFirst(RegExp('[.٫]\\d{1,2}\\s*\$'), '');
      if (caret > text.length) caret = text.length;
    }

    var before = _onlyDigits(text.substring(0, caret));
    var after = _onlyDigits(text.substring(caret));

    // حذف فاصلة وحدها: الفاصلة تعود فيعلق المؤشّر، فيُحذف الرقم المجاور.
    if (text.length == oldValue.text.length - 1 &&
        before + after == _onlyDigits(oldValue.text)) {
      final backspace = oldValue.selection.end > newValue.selection.end;
      if (backspace && before.isNotEmpty) {
        before = before.substring(0, before.length - 1);
      } else if (!backspace && after.isNotEmpty) {
        after = after.substring(1);
      }
    }

    final raw = before + after;
    if (raw.isEmpty) return TextEditingValue.empty;
    final digits = raw.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    // أطول من المسموح: يُرفض الإدخال كلّه، فقصّه بصمت مبلغٌ آخر.
    if (digits.length > _maxDigits) return oldValue;

    final grouped = _group(digits);
    // يبقى وراء المؤشّر العدد نفسه من الأرقام.
    var left = after.length < digits.length ? after.length : digits.length;
    var offset = grouped.length;
    while (left > 0) {
      offset--;
      if (grouped[offset] != ',') left--;
    }
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
