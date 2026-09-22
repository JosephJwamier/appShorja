import 'package:flutter/material.dart';
import '../models/reservation.dart';
import '../services/reservation_service.dart';

/// Tracks how many of the current user's reservations need their input right
/// now — drives the "حجوزاتي" bottom-nav badge, mirroring
/// ChatsProvider.unreadMessagesCount.
class ReservationsBadgeProvider extends ChangeNotifier {
  final _service = ReservationService();

  int _pendingActionCount = 0;
  int get pendingActionCount => _pendingActionCount;

  /// Background refresh — fetches its own copy of the list. Used at shell
  /// startup, before the user has ever opened the reservations tab.
  Future<void> load({
    required String accessToken,
    required int currentUserId,
  }) async {
    try {
      final all = await _service.fetchReservations(accessToken: accessToken);
      applyReservations(all, currentUserId: currentUserId);
    } catch (_) {
      // Silent — this is a background badge refresh, not a user-facing fetch.
    }
  }

  /// Recomputes the badge count from a list already fetched elsewhere (the
  /// reservations screen itself) — avoids a second network round-trip every
  /// time that screen loads or an action changes a reservation's status.
  void applyReservations(List<Reservation> all, {required int currentUserId}) {
    _pendingActionCount = all.where((r) => r.needsAction(currentUserId)).length;
    notifyListeners();
  }
}
