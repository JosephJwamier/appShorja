import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// يفتح قائمة المشاركة النظامية برابط https (App Link/Universal Link) بدل
/// custom scheme، حتى يفتح الرابط التطبيق مباشرة عند من لديه التطبيق مثبتاً،
/// ويفتح المتصفح (صفحة fallback) عند من لا يملكه.
Future<void> shareLink(
  BuildContext context, {
  required String text,
  String? subject,
}) {
  final box = context.findRenderObject() as RenderBox?;
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: subject,
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    ),
  );
}
