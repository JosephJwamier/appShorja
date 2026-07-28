import 'product.dart';
import 'store.dart';

/// A store the current user follows, paired with a preview of its products.
class FollowedStoreGroup {
  final Store store;
  final List<Product> items;

  FollowedStoreGroup({required this.store, required this.items});

  factory FollowedStoreGroup.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>?) ?? [];
    return FollowedStoreGroup(
      store: Store.fromJson(json['store'] as Map<String, dynamic>),
      items: itemsList
          .cast<Map<String, dynamic>>()
          .map((e) => Product.fromJson(e))
          .toList(),
    );
  }
}
