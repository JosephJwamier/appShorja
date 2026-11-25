import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/resale_agreement.dart';
import 'package:marketplace_app/models/wallet.dart';

Map<String, dynamic> _json([Map<String, dynamic> extra = const {}]) => {
      'id': 1,
      'item': {'id': 1, 'name': 't'},
      'owner': {'id': 1, 'username': 'o', 'email': '', 'phone': ''},
      'reseller': {'id': 2, 'username': 'r', 'email': '', 'phone': ''},
      'initiated_at': '2026-11-25T00:00:00Z',
      ...extra,
    };

void main() {
  test('an older server sends nothing about held money', () {
    final a = ResaleAgreement.fromJson(_json());
    expect(a.heldQuantity, 0);
    expect(a.paysImmediately, isNull);
    expect(a.escrowNotice, isNull);
    expect(a.canConfirmReceived, isFalse);
  });

  test('held money is read', () {
    final a = ResaleAgreement.fromJson(_json({
      'held_quantity': 3,
      'held_amount': 300000.0,
      'escrow_notice': 'x',
      'pays_immediately': false,
      'can_claim_handover': true,
    }));
    expect(a.heldAmount, 300000);
    expect(a.paysImmediately, isFalse);
    expect(a.canClaimHandover, isTrue);
  });

  test('withdrawable falls back to available', () {
    final base = {
      'balance': '10',
      'held_balance': '0',
      'available_balance': '10',
      'updated_at': '2026-11-25T00:00:00Z',
    };
    expect(Wallet.fromJson(base).withdrawableBalance, 10);
    expect(
      Wallet.fromJson({...base, 'withdrawable_balance': '4'})
          .withdrawableBalance,
      4,
    );
  });
}
