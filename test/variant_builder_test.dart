import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/widgets/product/variant_builder.dart';

void main() {
  group('VariantDraft', () {
    test('combinations are the cartesian product in declaration order', () {
      final draft = VariantDraft(options: [
        OptionDraft(name: 'Color', values: ['Red', 'Blue']),
        OptionDraft(name: 'Size', values: ['M', 'L']),
      ]);
      expect(draft.combinations, [
        {'Color': 'Red', 'Size': 'M'},
        {'Color': 'Red', 'Size': 'L'},
        {'Color': 'Blue', 'Size': 'M'},
        {'Color': 'Blue', 'Size': 'L'},
      ]);
    });

    test('rows survive the option list changing', () {
      final draft = VariantDraft(options: [
        OptionDraft(name: 'Color', values: ['Red']),
      ]);
      draft.rowFor({'Color': 'Red'}).quantity = 3;
      draft.options[0].values.add('Blue');
      expect(draft.rowFor({'Color': 'Red'}).quantity, 3);
      expect(draft.totalQuantity, 3);
    });

    test('serialises price only when set', () {
      final draft = VariantDraft(options: [
        OptionDraft(name: 'Size', values: ['M', 'L']),
      ]);
      draft.rowFor({'Size': 'M'})
        ..quantity = 5
        ..price = 150;
      draft.rowFor({'Size': 'L'}).quantity = 2;
      expect(draft.variantsJson(), [
        {'attributes': {'Size': 'M'}, 'quantity': 5, 'price': 150.0},
        {'attributes': {'Size': 'L'}, 'quantity': 2},
      ]);
      expect(draft.optionsJson(), [
        {'name': 'Size', 'values': ['M', 'L']},
      ]);
    });

    test('validate mirrors the server rules', () {
      expect(VariantDraft().validate(), isNotNull);
      expect(
        VariantDraft(options: [OptionDraft(name: '', values: ['x'])]).validate(),
        'كل خيار يحتاج اسماً',
      );
      expect(
        VariantDraft(options: [OptionDraft(name: 'A')]).validate(),
        'الخيار "A" بلا قيم',
      );
      expect(
        VariantDraft(options: [
          OptionDraft(name: 'A', values: ['1']),
          OptionDraft(name: 'A', values: ['2']),
        ]).validate(),
        'اسم الخيار "A" مكرّر',
      );
      final ok = VariantDraft(options: [OptionDraft(name: 'A', values: ['1'])]);
      expect(ok.validate(), 'أدخل كمية لمجموعة واحدة على الأقل');
      ok.rowFor({'A': '1'}).quantity = 1;
      expect(ok.validate(), isNull);
    });
  });

  group('VariantBuilder', () {
    Future<void> pump(WidgetTester tester, VariantDraft draft) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VariantBuilder(draft: draft, onChanged: () {}),
          ),
        ),
      ));
    }

    testWidgets('adding a value through the dialog does not crash on close',
        (tester) async {
      // Regression: the dialog's controller used to be disposed the moment
      // showDialog returned, while the TextField was still animating out —
      // a red screen (`_dependents.isEmpty`) on the device.
      final draft = VariantDraft(options: [OptionDraft(name: 'Color')]);
      await pump(tester, draft);

      await tester.tap(find.text('قيمة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Red');
      await tester.tap(find.text('إضافة'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(draft.options[0].values, ['Red']);
      expect(find.text('Red'), findsWidgets);
    });

    testWidgets('typed stock stays put when the table rebuilds', (tester) async {
      final draft = VariantDraft(options: [
        OptionDraft(name: 'Size', values: ['M', 'L']),
      ]);
      await pump(tester, draft);

      final qtyFields = find.widgetWithText(TextFormField, 'الكمية');
      await tester.enterText(qtyFields.first, '7');
      await tester.pump();
      expect(draft.rowFor({'Size': 'M'}).quantity, 7);

      // Add a value: every row rebuilds; M's field must still read 7.
      await tester.tap(find.text('قيمة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'XL');
      await tester.tap(find.text('إضافة'));
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
      expect(draft.combinations.length, 3);
      expect(draft.totalQuantity, 7);
    });
  });
}
