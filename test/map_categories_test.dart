import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/features/location/models/nearby_item_model.dart';
import 'package:marketplace_app/features/location/utils/map_categories.dart';
import 'package:marketplace_app/models/category.dart';

NearbyItem _item(int id, {int? catId, int? parent, String catName = 'x'}) {
  return NearbyItem.fromJson({
    'id': id,
    'owner': const {'id': 1},
    'title': 'item $id',
    'category': catId == null
        ? null
        : {'id': catId, 'name': catName, 'slug': 's', 'parent': parent},
    'created_at': '2026-11-17T00:00:00Z',
    'updated_at': '2026-11-17T00:00:00Z',
  });
}

void main() {
  // إلكترونيات(1) ← هواتف(11) ← آيفون(111)، وملابس(2) جذر بلا أبناء.
  final byId = {
    1: const Category(id: 1, name: 'Electronics', nameAr: 'إلكترونيات'),
    11: const Category(id: 11, name: 'Phones', nameAr: 'هواتف', parentId: 1),
    111: const Category(id: 111, name: 'iPhone', nameAr: 'آيفون', parentId: 11),
    2: const Category(id: 2, name: 'Clothes', nameAr: 'ملابس'),
  };

  test('a sub-sub-category item is counted under its root', () {
    expect(rootCategoryIdOf(_item(1, catId: 111, parent: 11), byId), 1);
  });

  test('without the category list, the embedded parent is used', () {
    expect(rootCategoryIdOf(_item(1, catId: 11, parent: 1), const {}), 1);
  });

  test('categories are grouped by root, biggest first, uncategorized last',
      () {
    final items = [
      _item(1, catId: 2),
      _item(2, catId: 111, parent: 11),
      _item(3, catId: 11, parent: 1),
      _item(4),
      _item(5),
      _item(6),
    ];
    final cats = mapCategoriesFor(items, byId);
    expect(cats.map((c) => c.id), [1, 2, -1]);
    expect(cats.map((c) => c.count), [2, 1, 3]);
    expect(cats.first.name, 'إلكترونيات');
  });

  test('filtering by a root keeps its descendants only', () {
    final phone = _item(1, catId: 111, parent: 11);
    final shirt = _item(2, catId: 2);
    final bare = _item(3);
    expect(itemMatchesCategory(phone, 1, byId), isTrue);
    expect(itemMatchesCategory(shirt, 1, byId), isFalse);
    expect(itemMatchesCategory(bare, -1, byId), isTrue);
    expect(itemMatchesCategory(phone, -1, byId), isFalse);
    expect(itemMatchesCategory(shirt, null, byId), isTrue);
  });

  test('a category keeps its colour wherever it sits in the strip', () {
    expect(colorForCategory(1), colorForCategory(1));
    expect(colorForCategory(null), kUncategorizedColor);
  });
}
