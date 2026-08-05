import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// صورة شبكية مع تخزين مؤقت (ذاكرة + قرص) — بديل مباشر لـ `Image.network`.
///
/// صُمّم ليطابق الوسائط المستخدمة فعليًا في التطبيق: عنوان الصورة موضعيًا
/// إضافةً إلى `fit` و`width` و`height` و`errorBuilder`. الاستبدال ميكانيكي:
/// يكفي تغيير `Image.network(` إلى `AppNetworkImage(` دون تغيير بقية الوسائط.
///
/// الفائدة: لا تُعاد صور المنتجات من الشبكة في كل مرة — تُحفظ على القرص
/// وتُعرض فورًا لاحقًا (أسرع + استهلاك بيانات أقل)، مع مُموِّه تحميل خفيف
/// وتلاشٍ لطيف عند الظهور.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  });

  /// عنوان الصورة (نفس أول وسيط موضعي في `Image.network`).
  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;

  /// نفس توقيع `Image.network.errorBuilder`. عند تمريره يُستخدم كما هو،
  /// وإلا يُعرض بديل رمادي بأيقونة صورة معطوبة.
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    // عنوان فارغ ⇐ اعرض حالة الخطأ مباشرة (يطابق سلوك Image.network مع رابط فارغ).
    if (url.isEmpty) {
      return errorBuilder?.call(context, 'empty url', null) ??
          _Box(width: width, height: height, child: _errorIcon);
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (context, _) => _Box(width: width, height: height),
      errorWidget: (context, _, error) =>
          errorBuilder?.call(context, error, null) ??
          _Box(width: width, height: height, child: _errorIcon),
    );
  }

  static const Widget _errorIcon =
      Icon(Icons.broken_image_outlined, color: Color(0xFFBDBDBD), size: 24);
}

/// حاوية رمادية محايدة تُستخدم كمُموِّه تحميل أو خلفية لحالة الخطأ.
class _Box extends StatelessWidget {
  const _Box({this.width, this.height, this.child});

  final double? width;
  final double? height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: const Color(0xFFEEEEEE),
      child: child,
    );
  }
}
