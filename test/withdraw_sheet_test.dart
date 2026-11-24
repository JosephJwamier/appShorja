import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/wallet.dart';
import 'package:marketplace_app/services/wallet_service.dart';
import 'package:marketplace_app/widgets/wallet/withdraw_sheet.dart';

class _FakeWallet extends WalletService {
  double? amount;
  String? account;
  String? holder;

  @override
  Future<void> withdraw({
    required double amount,
    required String accountNumber,
    required String holderName,
  }) async {
    this.amount = amount;
    account = accountNumber;
    holder = holderName;
  }
}

Future<_FakeWallet> _fill(
  WidgetTester tester, {
  required String amount,
  String account = '6330123456789012',
  String holder = 'علي',
}) async {
  final fake = _FakeWallet();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: WithdrawSheet(available: 100000, service: fake)),
  ));
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), amount);
  await tester.enterText(fields.at(1), account);
  await tester.enterText(fields.at(2), holder);
  await tester.tap(find.text('إرسال الطلب'));
  await tester.pump();
  return fake;
}

void main() {
  testWidgets('a valid request is sent with the amount read back whole',
      (tester) async {
    final fake = await _fill(tester, amount: '50000');
    expect(fake.amount, 50000);
    expect(fake.account, '6330123456789012');
    expect(fake.holder, 'علي');
    expect(find.text('50,000'), findsOneWidget);
  });

  testWidgets('more than the balance is refused', (tester) async {
    final fake = await _fill(tester, amount: '100001');
    expect(fake.amount, isNull);
    expect(find.text('أكبر من رصيدك المتاح'), findsOneWidget);
  });

  testWidgets('a destination is required', (tester) async {
    final fake =
        await _fill(tester, amount: '5000', account: '123', holder: ' ');
    expect(fake.amount, isNull);
  });

  test('statuses read in Arabic', () {
    Withdrawal w(String s) => Withdrawal.fromJson({
          'id': 1,
          'amount': '5000.00',
          'status': s,
          'card_last4': '9012',
          'admin_notes': '',
          'created_at': '2026-11-24T10:00:00Z',
        });
    expect(w('pending').statusLabel, 'قيد المراجعة');
    expect(w('approved').statusLabel, 'حُوّل');
    expect(w('rejected').statusLabel, 'مرفوض');
  });
}
