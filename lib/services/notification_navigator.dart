import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/active_representatives_screen.dart';
import '../screens/auction_details_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/received_requests_screen.dart';
import '../screens/reels/my_reels_screen.dart';
import '../screens/resale_agreements_screen.dart';
import '../screens/reservations_screen.dart';
import '../screens/sent_requests_screen.dart';
import '../screens/store_chat_screen.dart';
import 'auction_service.dart';

int? _asInt(dynamic value) =>
    value == null ? null : int.tryParse(value.toString());

/// Routes a tapped push notification to its concrete destination screen
/// (chat thread, auction, or reservations) based on the FCM `data` payload,
/// instead of dropping the user on the generic notifications list.
Future<void> navigateForNotificationTap(
  BuildContext context,
  String type,
  Map<String, dynamic> data,
) async {
  final navigator = Navigator.of(context);

  switch (type) {
    case 'new_message':
      final chatId = _asInt(data['chat_id'] ?? data['conversation_id']);
      if (chatId != null) {
        navigator.push(
          MaterialPageRoute(builder: (_) => StoreChatScreen(chatId: chatId)),
        );
        return;
      }
      break;

    case 'new_bid':
    case 'outbid':
      final auctionId = _asInt(data['auction_id']);
      final accessToken =
          Provider.of<AuthProvider>(context, listen: false).accessToken;
      if (auctionId != null && accessToken != null) {
        try {
          final auction = await AuctionService().fetchAuctionDetails(
            accessToken: accessToken,
            auctionId: auctionId,
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) => AuctionDetailsScreen(auction: auction),
            ),
          );
        } catch (_) {
          navigator.push(
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          );
        }
        return;
      }
      break;

    case 'auction_won':
    case 'reservation_created':
    case 'reservation_confirmed':
    case 'reservation_expiring':
    case 'reservation_completed':
    case 'payment_release_requested':
    case 'representative_sale':
    case 'representative_commission_paid':
      // 'auction_won' means a Reservation was created for the winner who
      // must now choose full payment vs. deposit+cash-at-delivery (same
      // choice as any other reservation) — so this lands on the
      // reservations list too, not the auction page. There's no
      // single-reservation detail screen yet, so the list is the best
      // available destination for all of these.
      navigator.push(
        MaterialPageRoute(builder: (_) => const ReservationsScreen()),
      );
      return;

    case 'representative_request':
      // Someone asked to represent one of the current user's items —
      // lands on the "incoming requests" inbox where they approve/reject.
      navigator.push(
        MaterialPageRoute(builder: (_) => const ReceivedRequestsScreen()),
      );
      return;

    case 'representative_rejected':
      // The current user's own request to represent an item was turned
      // down — this is where they sent it from.
      navigator.push(
        MaterialPageRoute(builder: (_) => const SentRequestsScreen()),
      );
      return;

    case 'representative_accepted':
    case 'representative_cancelled':
    case 'representative_permissions_updated':
      navigator.push(
        MaterialPageRoute(builder: (_) => const ActiveRepresentativesScreen()),
      );
      return;

    case 'resale_agreement_request':
    case 'resale_agreement_approved':
    case 'resale_agreement_rejected':
    case 'resale_agreement_cancelled':
      navigator.push(
        MaterialPageRoute(builder: (_) => const ResaleAgreementsScreen()),
      );
      return;

    case 'reel_liked':
    case 'reel_comment':
      // إلى «ريلزاتي» لا إلى موجز الريلز: الإشعار يخصّ ريلاً يملكه
      // المستخدم، وهناك يرى إعجاباته وتعليقاته ويردّ عليها.
      //
      // بلا هذا الفرع كان الإشعاران يسقطان على الافتراضي أدناه فيفتحان
      // قائمة الإشعارات — أي يعيدان المستخدم إلى حيث ضغط.
      navigator.push(
        MaterialPageRoute(builder: (_) => const MyReelsScreen()),
      );
      return;
  }

  navigator.push(
    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
  );
}
