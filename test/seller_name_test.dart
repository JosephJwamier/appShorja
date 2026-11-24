import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/user.dart';

void main() {
  User user(Map<String, dynamic> extra) =>
      User.fromJson({'id': 1, 'username': 'ali_77', ...extra});

  test('the store name is what buyers see', () {
    final u = user({'first_name': 'علي', 'store_name': 'متجر النور'});
    expect(u.sellerName, 'متجر النور');
    expect(u.username, 'ali_77');
    expect(u.copyWith(bio: 'x').sellerName, 'متجر النور');
  });

  test('without a store the personal name, then the username', () {
    expect(user({'first_name': 'علي', 'store_name': ''}).sellerName, 'علي');
    expect(user({}).sellerName, 'ali_77');
  });
}
