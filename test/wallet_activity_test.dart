import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/wallet.dart';
import 'package:marketplace_app/screens/wallet_activity_screen.dart';
import 'package:marketplace_app/widgets/wallet/sync_refresh_button.dart';

Map<String, dynamic> entry(String direction, {String kind = 'purchase', String note = ''}) => {
      'id': 'txn-1',
      'kind': kind,
      'direction': direction,
      'amount': '15000.00',
      'status': 'completed',
      'title': 'دفع ثمن حجز',
      'from': 'المحفظة',
      'to': 'حجز #174 — QA Shirt',
      'occurred_at': '2026-09-15T08:00:00Z',
      'ref_type': 'reservation',
      'ref_id': 174,
      'note': note,
    };

void main() {
  group('models', () {
    test('WalletActivity parses balances, escrow and entries', () {
      final a = WalletActivity.fromJson({
        'balance': '150000.00',
        'held_balance': '20000.00',
        'available_balance': '130000.00',
        'escrow': {'paid_waiting': '300.00', 'earnings_waiting': '0', 'commissions_waiting': '0'},
        'pending_topups': 1,
        'entries': [entry('hold', note: 'في الضمان'), entry('in', kind: 'topup')],
      });
      expect(a.availableBalance, 130000);
      expect(a.paidWaiting, 300);
      expect(a.pendingTopups, 1);
      expect(a.entries.map((e) => e.direction),
          [FlowDirection.hold, FlowDirection.inward]);
      expect(a.entries.first.counts, isFalse);
      expect(a.entries.last.counts, isTrue);
      expect(a.entries.first.refId, '174');
    });

    test('unknown directions fall back to pending, never to in', () {
      expect(MoneyFlowEntry.fromJson(entry('weird')).direction, FlowDirection.pending);
    });

    test('SyncResult builds the one-line outcome', () {
      expect(SyncResult.fromJson(const {}).message, 'تم التحديث — لا عمليات معلّقة');
      final r = SyncResult.fromJson({
        'checked': 3, 'settled': 1, 'still_pending': 1, 'failed': 0, 'errors': 1});
      expect(r.message, 'تم التحديث — اكتملت 1، ما زالت 1 بانتظار البوابة، تعذّر الاتصال بالبوابة لـ1');
    });
  });

  group('SyncRefreshButton', () {
    testWidgets('fires once per tap and is disabled while busy', (tester) async {
      var taps = 0;
      var busy = false;
      late StateSetter setOuter;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return Scaffold(
            appBar: AppBar(actions: [
              SyncRefreshButton(
                busy: busy,
                onPressed: () async {
                  taps++;
                },
              ),
            ]),
          );
        }),
      ));

      await tester.tap(find.byType(SyncRefreshButton));
      expect(taps, 1);

      setOuter(() => busy = true);
      await tester.pump();
      await tester.tap(find.byType(SyncRefreshButton), warnIfMissed: false);
      expect(taps, 1, reason: 'a spinning arrow must not start a second sync');

      // The rotation animation is running; stopping it must not throw.
      await tester.pump(const Duration(milliseconds: 300));
      setOuter(() => busy = false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('MoneyFlowTile', () {
    testWidgets('shows sign, from → to and the note', (tester) async {
      final e = MoneyFlowEntry.fromJson(entry('out', note: 'سُلّم للبائع'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MoneyFlowTile(entry: e)),
      ));
      expect(find.text('−15,000'), findsOneWidget);
      expect(find.text('المحفظة'), findsOneWidget);
      expect(find.text('حجز #174 — QA Shirt'), findsOneWidget);
      expect(find.text('خارج'), findsOneWidget);
      expect(find.text('سُلّم للبائع'), findsOneWidget);
    });

    testWidgets('held money carries no sign and says so', (tester) async {
      final e = MoneyFlowEntry.fromJson(entry('hold'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MoneyFlowTile(entry: e)),
      ));
      expect(find.text('15,000'), findsOneWidget);
      expect(find.text('محجوز'), findsOneWidget);
    });
  });
}
