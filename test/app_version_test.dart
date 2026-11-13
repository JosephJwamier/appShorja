// شاشة «حدّث التطبيق» تقفل التطبيق كلّه، فخطؤها في أي اتجاه مكلف:
// ألّا تظهر لنسخة معطوبة، أو أن تظهر لنسخة سليمة فتقفلها على صاحبها.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/services/app_version_service.dart';

void main() {
  VersionPolicy floor(int min) => VersionPolicy(minBuild: min, storeUrl: '');

  test('an older build is blocked', () {
    expect(floor(5).blocks(4), isTrue);
  });

  test('the minimum build itself is still served', () {
    expect(floor(5).blocks(5), isFalse);
  });

  test('a newer build passes', () {
    expect(floor(5).blocks(9), isFalse);
  });

  test('a zero minimum blocks nobody', () {
    expect(floor(0).blocks(1), isFalse);
  });

  test('an unreadable build number is never locked out', () {
    // قراءة رقم البنية فشلت (0): خطؤنا نحن لا يقفل التطبيق على صاحبه.
    expect(floor(5).blocks(0), isFalse);
  });

  test('parses the server reply, tolerating missing fields', () {
    final p = VersionPolicy.fromJson(
        {'min_build': 3, 'store_url': 'https://play.google.com/x'});
    expect((p.minBuild, p.storeUrl), (3, 'https://play.google.com/x'));
    final empty = VersionPolicy.fromJson({});
    expect((empty.minBuild, empty.storeUrl), (0, ''));
  });
}
