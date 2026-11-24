import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/utils/amount_input.dart';

const _f = AmountInputFormatter();

/// "12|3": النصّ والمؤشّر معاً.
TextEditingValue _v(String s) {
  final at = s.indexOf('|');
  return TextEditingValue(
    text: s.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: at),
  );
}

String _edit(String from, String to) {
  final r = _f.formatEditUpdate(_v(from), _v(to));
  final at = r.selection.end < 0 ? r.text.length : r.selection.end;
  return '${r.text.substring(0, at)}|${r.text.substring(at)}';
}

String _type(String keys) {
  var value = _v('|');
  for (final k in keys.split('')) {
    final at = value.selection.end < 0 ? 0 : value.selection.end;
    value = _f.formatEditUpdate(
      value,
      TextEditingValue(
        text: value.text.replaceRange(at, at, k),
        selection: TextSelection.collapsed(offset: at + 1),
      ),
    );
  }
  return value.text;
}

void main() {
  test('separators appear while typing', () {
    expect(_type('999'), '999');
    expect(_type('1000'), '1,000');
    expect(_type('1000000'), '1,000,000');
  });

  test('a dot is a thousands mark, never a decimal', () {
    expect(_type('25.000'), '25,000');
  });

  test('Arabic and Persian digits are accepted', () {
    expect(_type('٢٥٠٠٠'), '25,000');
    expect(_type('۲۵۰۰۰'), '25,000');
    expect(parseAmount('٢٥٬٠٠٠'), 25000);
  });

  test('pasting', () {
    expect(_edit('|', '25000.00|'), '25,000|');
    expect(_edit('|', '1,250,000 د.ع|'), '1,250,000|');
    expect(_edit('|', '25.000|'), '25,000|');
  });

  test('the caret keeps its place in the middle', () {
    expect(_edit('1,|234', '19|,234'), '19,|234');
    expect(_edit('12|3', '129|3'), '1,29|3');
  });

  test('deleting a separator deletes the digit beside it', () {
    expect(_edit('1,|234', '1|234'), '|234');
    expect(_edit('1|,234', '1|234'), '1|34');
  });

  test('leading zeros go, a lone zero stays, emptying works', () {
    expect(_type('007'), '7');
    expect(_type('0'), '0');
    expect(_edit('5|', '|'), '|');
  });

  test('a number too long is refused, not trimmed', () {
    expect(_type('12345678901'), '1,234,567,890');
    expect(_edit('5|', '123456789012|'), '5|');
  });

  test('what is shown reads back as the same amount', () {
    for (final n in [0, 5, 999, 1000, 25000, 1000000]) {
      expect(parseAmount(amountText(n)), n);
    }
    expect(amountText(null), '');
    expect(parseAmount(''), isNull);
    expect(parseAmount(null), isNull);
    expect(parseAmount('2.5'), 2.5);
  });
}
