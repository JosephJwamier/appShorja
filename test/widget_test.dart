// Smoke test for the real login screen — the previous version of this file
// was still the unmodified `flutter create` counter-app template, which
// doesn't match anything in this app's actual widget tree (there is no
// counter, and `MyApp` renders `AuthGate`, not a bare counter page).
//
// `LoginScreen` only reads `AuthProvider` during build (`Consumer<AuthProvider>`
// for the submit button's loading state) — `NotificationsProvider`/
// `ChatsProvider` are only touched inside button-press handlers, so they're
// not needed just to render the screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:marketplace_app/providers/auth_provider.dart';
import 'package:marketplace_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders the username field and submit button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.byType(TextField), findsAtLeastNWidgets(2));
    expect(find.text('تسجيل الدخول'), findsWidgets);
  });
}
