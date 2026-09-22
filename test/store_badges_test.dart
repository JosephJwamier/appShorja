import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/store.dart';
import 'package:marketplace_app/models/user.dart';
import 'package:marketplace_app/widgets/store/store_badges.dart';

void main() {
  group('models', () {
    test('User parses store_badges and keeps them through copyWith', () {
      final u = User.fromJson({
        'id': 1, 'username': 'x', 'email': '', 'phone': '',
        'store_badges': ['founder', 'gold'],
      });
      expect(u.storeBadges, ['founder', 'gold']);
      expect(u.copyWith(bio: 'b').storeBadges, ['founder', 'gold']);
      expect(User.fromJson({'id': 2, 'username': 'y', 'email': '', 'phone': ''}).storeBadges, isEmpty);
    });

    test('Store parses level and badges', () {
      final s = Store.fromJson({
        'id': 5, 'user': {'id': 1, 'username': 'x', 'email': '', 'phone': ''},
        'name': 'n', 'created_at': '2026-09-17T00:00:00Z',
        'level': 'silver', 'badges': ['verified', 'silver'],
      });
      expect(s.level, 'silver');
      expect(s.badges, ['verified', 'silver']);
    });
  });

  group('catalogue', () {
    test('every badge kind the server can send has an asset and an Arabic name', () {
      const serverKinds = ['founder', 'pioneer', 'certified', 'verified',
                           'bronze', 'silver', 'gold', 'diamond'];
      for (final k in serverKinds) {
        expect(kStoreBadges[k], isNotNull, reason: k);
        expect(kStoreBadges[k]!.name, isNotEmpty);
        expect(kStoreBadges[k]!.asset, 'assets/badges/$k.svg');
      }
    });
  });

  group('widgets', () {
    Widget host(Widget child) => MaterialApp(
          home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
        );

    testWidgets('renders one SVG per known kind and labels the first', (tester) async {
      await tester.pumpWidget(host(const StoreBadgesRow(kinds: ['founder', 'verified', 'gold'])));
      await tester.pump();
      expect(find.byType(SvgPicture), findsNWidgets(3));
      expect(find.text('مؤسِّس'), findsOneWidget);
      expect(find.text('موثَّق'), findsNothing);
    });

    testWidgets('compact form is icons only and caps at three', (tester) async {
      await tester.pumpWidget(host(const StoreBadgesRow(
        kinds: ['founder', 'pioneer', 'verified', 'gold'], compact: true)));
      await tester.pump();
      expect(find.byType(SvgPicture), findsNWidgets(3));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('unknown kinds from a newer server render nothing, not an error', (tester) async {
      await tester.pumpWidget(host(const StoreBadgesRow(kinds: ['platinum'])));
      await tester.pump();
      expect(find.byType(SvgPicture), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shipped SVG assets load', (tester) async {
      await tester.pumpWidget(host(const StoreBadgeIcon(kind: 'diamond', size: 48, withLabel: true)));
      await tester.pumpAndSettle();
      expect(find.text('ماسي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
