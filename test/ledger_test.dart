import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/ledger.dart';
import 'package:marketplace_app/providers/ledger_provider.dart';
import 'package:marketplace_app/screens/ledger/ledger_entries_screen.dart';
import 'package:marketplace_app/widgets/ledger/sales_bar_chart.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _entryJson({
  int id = 1,
  String kind = 'sale_cash',
  String amount = '15000.00',
  String? contact,
  String source = 'manual',
  bool isVoid = false,
}) =>
    {
      'id': id,
      'kind': kind,
      'amount': amount,
      'contact': contact == null ? null : 7,
      'contact_name': contact,
      'note': 'n',
      'occurred_at': '2026-09-14T09:30:00Z',
      'expense_category': kind == 'expense' ? 'rent' : '',
      'item': 115,
      'item_title': 'QA Shirt',
      'variant': 9,
      'variant_label': 'Blue / M',
      'quantity': 2,
      'cost_amount': null,
      'receipt_url': null,
      'source': source,
      'reservation': null,
      'is_void': isVoid,
      'void_reason': isVoid ? 'مكرّر' : '',
      'created_at': '2026-09-14T09:31:00Z',
    };

void main() {
  group('LedgerKind', () {
    test('knows which contact each kind needs', () {
      expect(LedgerKind.saleCredit.contactKind, ContactKind.customer);
      expect(LedgerKind.paymentIn.contactKind, ContactKind.customer);
      expect(LedgerKind.purchase.contactKind, ContactKind.supplier);
      expect(LedgerKind.paymentOut.contactKind, ContactKind.supplier);
      expect(LedgerKind.saleCash.contactKind, isNull);
      expect(LedgerKind.expense.contactKind, isNull);
    });

    test('app sales are never offered for manual entry', () {
      expect(LedgerKind.manual, isNot(contains(LedgerKind.saleApp)));
      expect(LedgerKind.fromValue('sale_app'), LedgerKind.saleApp);
      expect(LedgerKind.fromValue('garbage'), LedgerKind.saleCash);
    });
  });

  group('models', () {
    test('LedgerEntry parses decimals-as-strings and builds a subtitle', () {
      final e = LedgerEntry.fromJson(_entryJson(contact: 'أبو علي'));
      expect(e.amount, 15000);
      expect(e.kind, LedgerKind.saleCash);
      expect(e.fromApp, isFalse);
      expect(e.subtitle, 'أبو علي · QA Shirt — Blue / M ×2 · n');
    });

    test('expense subtitle names the category', () {
      final e = LedgerEntry.fromJson(_entryJson(kind: 'expense')..['item'] = null..['item_title'] = null);
      expect(e.subtitle, contains('إيجار'));
    });

    test('StoreDashboard tolerates a sparse payload', () {
      final d = StoreDashboard.fromJson({
        'period': {'key': 'today'},
        'summary': {
          'start': '2026-09-14T00:00:00+03:00',
          'end': '2026-09-15T00:00:00+03:00',
          'revenue': '100.00',
          'expenses': '30.00',
          'net': '70.00',
          'gross_profit': null,
          'daily': [
            {'day': '2026-09-14', 'local': '100.00', 'app': '0', 'out': '30.00'},
          ],
        },
        'previous': {'revenue': '50.00'},
        'balances': {
          'receivables': '45000.00',
          'payables': '0',
          'debtors_count': 1,
          'top_debtors': [
            {'id': 3, 'kind': 'customer', 'name': 'مدين', 'balance': '45000.00'},
          ],
        },
        'stock': {'active_items': 2, 'sold_out_items': 0, 'low_stock': []},
        'orders': {'pending': 1, 'awaiting_handover': 0},
        'followers': 4,
        'rating': '4.50',
        'top_items': [],
      });
      expect(d.summary.revenue, 100);
      expect(d.summary.grossProfit, isNull);
      expect(d.summary.daily.single.sales, 100);
      expect(d.previousRevenue, 50);
      expect(d.receivables, 45000);
      expect(d.topDebtors.single.name, 'مدين');
      expect(d.pendingOrders, 1);
      expect(d.rating, 4.5);
    });

    test('ContactStatement carries running balances', () {
      final s = ContactStatement.fromJson({
        'contact': {'id': 3, 'kind': 'customer', 'name': 'م', 'balance': '20.00'},
        'balance': '20.00',
        'rows': [
          {'entry': _entryJson(kind: 'sale_credit', amount: '50.00'), 'running_balance': '50.00'},
          {'entry': _entryJson(id: 2, kind: 'payment_in', amount: '30.00'), 'running_balance': '20.00'},
        ],
      });
      expect(s.rows.map((r) => r.runningBalance), [50, 20]);
      expect(s.balance, 20);
    });
  });

  group('LedgerProvider', () {
    test('refreshAfterWrite bumps the revision so lists refetch', () {
      final p = LedgerProvider();
      expect(p.revision, 0);
      // The network calls fail in tests (no server) but must not throw out.
      expect(() => p.refreshAfterWrite(), returnsNormally);
      expect(p.revision, 1);
    });
  });

  group('widgets', () {
    testWidgets('SalesBarChart fills missing days and paints without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SalesBarChart(
            points: [
              DailyPoint(day: DateTime(2026, 9, 2), local: 100, app: 50, out: 20),
            ],
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 8),
          ),
        ),
      ));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(find.text('المحل'), findsOneWidget);
    });

    testWidgets('SalesBarChart says so when the period is empty', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SalesBarChart(
            points: const [],
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 8),
          ),
        ),
      ));
      expect(find.text('لا حركة في هذه الفترة'), findsOneWidget);
    });

    testWidgets('LedgerEntryTile shows sign, colour and void state', (tester) async {
      final inEntry = LedgerEntry.fromJson(_entryJson());
      final outEntry = LedgerEntry.fromJson(_entryJson(id: 2, kind: 'expense', amount: '30000'));
      final voided = LedgerEntry.fromJson(_entryJson(id: 3, isVoid: true));
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LedgerProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [
              LedgerEntryTile(entry: inEntry),
              LedgerEntryTile(entry: outEntry),
              LedgerEntryTile(entry: voided),
            ]),
          ),
        ),
      ));
      expect(find.text('+15,000'), findsNWidgets(2)); // the live one and the voided one
      expect(find.text('−30,000'), findsOneWidget);
      expect(find.textContaining('ملغى — مكرّر'), findsOneWidget);
    });
  });
}
