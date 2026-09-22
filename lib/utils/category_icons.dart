import 'package:flutter/material.dart';

/// أيقونات التصنيفات المسموح بها، مفهرسة برمز Material الرقمي الذي يكتبه
/// المشرف في حقل `Category.icon` في لوحة التحكم.
///
/// لماذا جدول ثابت بدل `IconData(code, fontFamily: 'MaterialIcons')` مباشرة؟
/// لأن `flutter build --release` يحذف من خط الأيقونات كل رمز لا يُشار إليه
/// بثابت (tree-shaking)، ويرفض البناء أصلًا إن وجد `IconData` يُنشأ من قيمة
/// غير ثابتة وقت التشغيل. الجدول يُبقي البناء الافتراضي يعمل ويُبقي حجم
/// الخط صغيرًا: ما يصل من الخادم يُبحث عنه هنا، وما ليس هنا يسقط إلى
/// [Icons.category_outlined] عبر [categoryIconFor].
///
/// المفاتيح هي `Icons.<name>.codePoint` بالضبط (مأخوذة من icons.dart في
/// Flutter SDK) — لا تُكتب `.codePoint` هنا لأن الوصول إلى حقل ليس تعبيرًا
/// ثابتًا في Dart، والخريطة يجب أن تبقى `const`.
const Map<int, IconData> kCategoryIcons = {
  // إلكترونيات
  0xe4a3: Icons.phone_android,
  0xe369: Icons.laptop_mac,
  0xe63e: Icons.tablet_android,
  0xe687: Icons.tv,
  0xe130: Icons.camera_alt,
  0xe5e8: Icons.sports_esports,
  0xe6aa: Icons.videogame_asset,
  0xe11e: Icons.cable,
  0xe4ea: Icons.print,
  0xe542: Icons.router,
  0xe1cb: Icons.devices,
  0xe2ff: Icons.headphones,
  0xe5db: Icons.speaker,
  // مركبات
  0xe1d7: Icons.directions_car,
  0xe689: Icons.two_wheeler,
  0xe3a6: Icons.local_shipping,
  0xe116: Icons.build,
  0xe54d: Icons.sailing,
  0xe483: Icons.pedal_bike,
  // أزياء
  0xe15d: Icons.checkroom,
  0xf05ab: Icons.woman,
  0xe160: Icons.child_care,
  0xe313: Icons.hiking,
  0xe59a: Icons.shopping_bag,
  0xe6ce: Icons.watch,
  0xf04ed: Icons.diamond,
  0xf053e: Icons.mosque,
  0xe6bd: Icons.visibility,
  // منزل
  0xe318: Icons.home,
  0xe14d: Icons.chair,
  0xe35e: Icons.kitchen,
  0xe0d7: Icons.bed,
  0xe37b: Icons.lightbulb,
  0xe6fb: Icons.yard,
  0xe2f2: Icons.handyman,
  0xf0795: Icons.curtains,
  0xe167: Icons.cleaning_services,
  // جمال وصحة
  0xe5d8: Icons.spa,
  0xe252: Icons.face,
  0xe393: Icons.local_florist,
  0xe191: Icons.content_cut,
  0xe3d8: Icons.medical_services,
  0xe3d9: Icons.medication,
  0xe113: Icons.brush,
  // رياضة
  0xe5f2: Icons.sports_soccer,
  0xe28d: Icons.fitness_center,
  0xe41b: Icons.nature_people,
  0xe4dc: Icons.pool,
  0xf056f: Icons.sports_martial_arts,
  0xf0548: Icons.phishing,
  0xe143: Icons.casino,
  // أطفال
  0xe672: Icons.toys,
  0xe0c3: Icons.baby_changing_station,
  0xe1a2: Icons.crib,
  0xe250: Icons.extension,
  // متفرقات
  0xe3dd: Icons.menu_book,
  0xe559: Icons.school,
  0xe6f2: Icons.work,
  0xe4a1: Icons.pets,
  0xe532: Icons.restaurant,
  0xe395: Icons.local_grocery_store,
  0xe60c: Icons.storefront,
  0xe063: Icons.agriculture,
  0xe189: Icons.construction,
  0xe228: Icons.electrical_services,
  0xe4d5: Icons.plumbing,
  0xe141: Icons.carpenter,
  0xe148: Icons.category,
};

/// أيقونة التصنيف لرمز قادم من الخادم، أو `null` إن كان الرمز فارغًا أو غير
/// مدرج في [kCategoryIcons] — فيختار المستدعي بديله (عادةً
/// [Icons.category_outlined]).
IconData? categoryIconFor(int? code) => code == null ? null : kCategoryIcons[code];
