// TODO: بدّل هذا القيمة بالدومين الفعلي بعد شرائه (مثال: https://eshorja.com).
// نفس الدومين لازم يستضيف:
//   - /.well-known/assetlinks.json (Android App Links)
//   - /.well-known/apple-app-site-association (iOS Universal Links)
//   - صفحات fallback على المسارات نفسها بالأسفل، لعرض معاينة + زر تحميل
//     التطبيق لمن يفتح الرابط بدون التطبيق مثبّت.
const String kWebDomain = 'https://REPLACE_WITH_YOUR_DOMAIN.example';

class DeepLinkConfig {
  const DeepLinkConfig._();

  static String productLink(int listingId) => '$kWebDomain/p/$listingId';
  static String storeLink(int storeId) => '$kWebDomain/s/$storeId';
  static String auctionLink(int auctionId) => '$kWebDomain/a/$auctionId';
  static String liveLink(int sessionId) => '$kWebDomain/l/$sessionId';
}
