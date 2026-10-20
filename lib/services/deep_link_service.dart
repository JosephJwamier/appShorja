import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/auction_details_screen.dart';
import '../screens/live/live_viewer_screen.dart';
import '../screens/product_details_screen.dart';
import '../screens/store_profile_screen.dart';
import 'auction_service.dart';
import 'item_service.dart';
import 'store_service.dart';

/// يستقبل روابط المشاركة (Android App Links / iOS Universal Links) ويفتح
/// الشاشة المطابقة، بنفس نمط navigateForNotificationTap لكن مصدر الحدث هنا
/// رابط https بدل إشعار.
///
/// المسارات المتوقعة: `/p/listingId`، `/s/storeId`، `/a/auctionId`،
/// `/l/sessionId` — يجب أن تطابق ما تولّده صفحات fallback على الباك اند
/// (انظر deep_link_config.dart).
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  void init(GlobalKey<NavigatorState> navigatorKey) {
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri, navigatorKey);
    });
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _handle(uri, navigatorKey),
    );
  }

  void dispose() => _subscription?.cancel();

  Future<void> _handle(Uri uri, GlobalKey<NavigatorState> navigatorKey) async {
    final segments = uri.pathSegments;
    if (segments.length < 2) return;

    final navigator = navigatorKey.currentState;
    final context = navigatorKey.currentContext;
    if (navigator == null || context == null) return;

    final id = int.tryParse(segments[1]);
    if (id == null) return;

    // لا يُشترط حساب. الرابط المشارَك هو أقوى دعوة للتسجيل يملكها
    // التطبيق، وابتلاعه بصمت لأن فاتحه ضيف يهدرها: يضغط الرابط، يُفتح
    // التطبيق، ولا يحدث شيء — فيظنّه معطّلاً لا مقفلاً.
    //
    // الخادم صار يسمح بقراءة المنتجات والمتاجر والمزادات للضيوف، وبوابة
    // الحساب تظهر عند الحجز أو المزايدة لا عند النظر.
    final accessToken =
        Provider.of<AuthProvider>(context, listen: false).accessToken;

    switch (segments[0]) {
      case 'p':
        try {
          final listing = await ItemService().fetchListingById(
            accessToken: accessToken,
            listingId: id,
          );
          if (listing != null) {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => ProductDetailsScreen(listing: listing),
              ),
            );
          }
        } catch (_) {}
        break;

      case 's':
        try {
          final store = await StoreService().fetchStoreById(
            accessToken: accessToken,
            storeId: id,
          );
          if (store != null) {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => StoreProfileScreen(store: store),
              ),
            );
          }
        } catch (_) {}
        break;

      case 'a':
        try {
          final auction = await AuctionService().fetchAuctionDetails(
            accessToken: accessToken,
            auctionId: id,
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AuctionDetailsScreen(auction: auction),
            ),
          );
        } catch (_) {}
        break;

      case 'l':
        // رابط بث يفتحه ضيف هو الطريق الأكثر احتمالاً لوصول مستخدم جديد —
        // فيُطلب منه الحساب، لا أن تُعرض له رسالة خطأ بالإنجليزية.
        await openLiveViewer(context, id);
        break;
    }
  }
}
