import 'package:flutter/material.dart';
import '../../../models/category.dart';
import '../models/nearby_item_model.dart';

/// تصنيف رئيسي ظاهر على الخريطة مع عدد منتجاته القريبة ولونه.
///
/// المنتج يحمل تصنيفه الفرعي غالباً ("هواتف")، لكن المستخدم يختار بالرئيسي
/// ("إلكترونيات")، فكل منتج يُنسب إلى جذر تصنيفه قبل العدّ والتصفية.
class MapCategory {
  final int id;
  final String name;
  final int? iconCode;
  final String? iconUrl;
  final int count;
  final Color color;

  const MapCategory({
    required this.id,
    required this.name,
    required this.count,
    required this.color,
    this.iconCode,
    this.iconUrl,
  });
}

/// ألوان العلامات حسب التصنيف. البرتقالي محجوز للمتاجر والأزرق لموقع
/// المستخدم، فلا يظهر أيّ منهما هنا حتى لا يلتبس منتج بمتجر.
const kMapCategoryPalette = <Color>[
  Color(0xFF00796B), // فيروزي
  Color(0xFF7B1FA2), // بنفسجي
  Color(0xFFC2185B), // وردي غامق
  Color(0xFF2E7D32), // أخضر
  Color(0xFF5D4037), // بنّي
  Color(0xFF0277BD), // أزرق بحري
  Color(0xFF827717), // زيتوني
  Color(0xFF4527A0), // نيلي
];

/// لون المنتجات التي لا تصنيف لها.
const kUncategorizedColor = Color(0xFF546E7A);

/// اللون ثابت لكل تصنيف (من رقمه) لا من ترتيبه في الشريط، كي لا تتبدّل
/// ألوان العلامات كلما تغيّر نطاق البحث وتغيّر ترتيب الأعداد.
Color colorForCategory(int? rootId) => rootId == null
    ? kUncategorizedColor
    : kMapCategoryPalette[rootId % kMapCategoryPalette.length];

/// رقم التصنيف الرئيسي لمنتج، أو null إن لم يكن له تصنيف.
///
/// [byId] هي قائمة التصنيفات المسطّحة من الخادم. إن لم تُحمَّل بعد نكتفي
/// بالأب المباشر المضمّن في المنتج، وهو الجذر في شجرة من مستويين.
int? rootCategoryIdOf(NearbyItem item, Map<int, Category> byId) {
  final c = item.category;
  if (c == null) return null;
  var id = c.id;
  var parent = byId[id]?.parentId ?? c.parent;
  // حدّ للعمق يحمي من حلقة إن أفسد أحدهم الشجرة من لوحة التحكم.
  for (var depth = 0; parent != null && depth < 6; depth++) {
    id = parent;
    parent = byId[id]?.parentId;
  }
  return id;
}

/// التصنيفات الموجودة فعلاً بين [items]، الأكثر منتجات أولاً.
///
/// نبني الشريط من المنتجات المحمّلة لا من كل تصنيفات المتجر: زرّ لتصنيف
/// بلا منتجات قريبة يُفرغ الخريطة ولا يفيد المستخدم بشيء.
List<MapCategory> mapCategoriesFor(
  List<NearbyItem> items,
  Map<int, Category> byId,
) {
  final counts = <int?, int>{};
  final fallbackNames = <int, String>{};
  for (final item in items) {
    final root = rootCategoryIdOf(item, byId);
    counts[root] = (counts[root] ?? 0) + 1;
    // إن كان المنتج في الجذر نفسه فاسم تصنيفه هو اسم الجذر.
    if (root != null && item.category?.id == root) {
      fallbackNames[root] = item.category!.name;
    }
  }

  final result = <MapCategory>[];
  counts.forEach((id, count) {
    if (id == null) {
      result.add(MapCategory(
        id: -1,
        name: 'بدون تصنيف',
        count: count,
        color: kUncategorizedColor,
      ));
      return;
    }
    final cat = byId[id];
    result.add(MapCategory(
      id: id,
      name: cat?.displayName ?? fallbackNames[id] ?? 'تصنيف $id',
      iconCode: cat?.iconCode,
      iconUrl: cat?.iconUrl,
      count: count,
      color: colorForCategory(id),
    ));
  });

  result.sort((a, b) {
    // «بدون تصنيف» آخراً دائماً مهما كان عدده.
    if (a.id == -1) return 1;
    if (b.id == -1) return -1;
    return b.count.compareTo(a.count);
  });
  return result;
}

/// هل ينتمي [item] إلى التصنيف المختار؟ null تعني «الكل»، و-1 «بدون تصنيف».
bool itemMatchesCategory(
  NearbyItem item,
  int? selectedId,
  Map<int, Category> byId,
) {
  if (selectedId == null) return true;
  final root = rootCategoryIdOf(item, byId);
  return selectedId == -1 ? root == null : root == selectedId;
}
