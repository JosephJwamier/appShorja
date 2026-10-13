// النطاق الفعلي. لازم يستضيف:
//   - /.well-known/assetlinks.json (Android App Links)
//   - /.well-known/apple-app-site-association (iOS Universal Links)
//   - صفحات fallback على المسارات نفسها بالأسفل، لعرض معاينة + زر تحميل
//     التطبيق لمن يفتح الرابط بدون التطبيق مثبّت.
// يجب أن يطابق android:host في AndroidManifest.xml حرفياً.
const String kWebDomain = 'https://shorjeh.com';

class DeepLinkConfig {
  const DeepLinkConfig._();

  static String productLink(int listingId) => '$kWebDomain/p/$listingId';
  static String storeLink(int storeId) => '$kWebDomain/s/$storeId';
  static String auctionLink(int auctionId) => '$kWebDomain/a/$auctionId';
  static String liveLink(int sessionId) => '$kWebDomain/l/$sessionId';
}
