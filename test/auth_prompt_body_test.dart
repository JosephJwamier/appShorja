// AuthPromptBody مشترك بين ورقة البوابة وتبويب الحساب للضيف. ما يحرسه
// هذا الملف هو أن النسختين تعرضان الطريقين معاً: شاشة لا تعرض إلا
// «تسجيل الدخول» تحبس من لا حساب له في طريق مسدود.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/utils/auth_gate.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('يعرض الطريقين: الدخول وإنشاء حساب', (tester) async {
    await tester.pumpWidget(_wrap(const AuthPromptBody(
      title: 'حسابك في الشورجة',
      subtitle: 'سجّل الدخول لمتابعة طلباتك.',
      showDismiss: false,
    )));

    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    expect(find.text('حسابك في الشورجة'), findsOneWidget);
  });

  testWidgets('«أكمل التصفّح» يظهر في الورقة ويغيب عن التبويب',
      (tester) async {
    // التبويب لا يُغلق، فزرّ الصرف فيه يقود إلى لا شيء.
    await tester.pumpWidget(_wrap(const AuthPromptBody(
      title: 'ع',
      subtitle: 'ن',
      showDismiss: false,
    )));
    expect(find.text('أكمل التصفّح'), findsNothing);

    await tester.pumpWidget(_wrap(const AuthPromptBody(
      title: 'ع',
      subtitle: 'ن',
      showDismiss: true,
    )));
    expect(find.text('أكمل التصفّح'), findsOneWidget);
  });
}
