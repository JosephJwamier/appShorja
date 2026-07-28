import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';

/// Holds the conversations inbox list, loaded once at login (mirrors
/// NotificationsProvider's load-once pattern) and refreshed on demand
/// (pull-to-refresh, or after returning from an open thread).
class ChatsProvider extends ChangeNotifier {
  final ChatService _service = ChatService();

  List<ChatSummary> _chats = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _nextPageUrl;
  String? _accessToken;
  bool _archived = false;

  List<ChatSummary> get chats => _chats;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _nextPageUrl != null;
  int get unreadMessagesCount =>
      _chats.fold(0, (sum, c) => sum + c.unreadCount);

  Future<void> load({required String accessToken, bool archived = false}) async {
    _accessToken = accessToken;
    _archived = archived;
    _isLoading = true;
    notifyListeners();

    final page =
        await _service.listChats(accessToken: accessToken, archived: archived);
    _chats = page.results;
    _nextPageUrl = page.next;

    _isLoading = false;
    notifyListeners();
  }

  /// Re-fetches page one in the background — unlike [load], doesn't flip
  /// [isLoading] (no spinner), so it's safe to call whenever a "new_message"
  /// FCM push arrives in the foreground without disrupting whatever screen
  /// the user is currently on. This is the only thing that keeps the unread
  /// badge/list fresh while the user isn't actively on the chats screen or
  /// inside the affected thread (both of which already refresh on their own).
  Future<void> refreshSilently() async {
    if (_accessToken == null) return;
    final page =
        await _service.listChats(accessToken: _accessToken!, archived: _archived);
    _chats = page.results;
    _nextPageUrl = page.next;
    notifyListeners();
  }

  /// Applies a "new_message" FCM push directly to the already-loaded list —
  /// no network call — by bumping that chat's unread count/preview and
  /// moving it to the top, the same way the backend's `-updated_at`
  /// ordering would. [refreshSilently] did this correctly but always paid
  /// for a full `GET /chats/` round-trip; this removes that hop for the
  /// common case (the chat is already in the loaded list). Falls back to
  /// [refreshSilently] only the first time a chat is ever seen (its store/
  /// item/avatar info isn't in the push payload, so it can't be
  /// reconstructed locally) or while viewing the archived list (a message
  /// there should actually surface through the main inbox, which a local
  /// patch can't do).
  Future<void> handleIncomingMessagePush(Map<String, dynamic> data) async {
    if (_archived) return;
    final chatId = int.tryParse(data['chat_id']?.toString() ?? '');
    if (chatId == null) {
      await refreshSilently();
      return;
    }

    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) {
      await refreshSilently();
      return;
    }

    final updated = _chats[idx].copyWith(
      lastMessageContent: data['content']?.toString(),
      lastMessageType: data['message_type']?.toString(),
      lastMessageAt: DateTime.tryParse(data['created_at']?.toString() ?? ''),
      lastMessageIsRead: false,
      unreadCount: _chats[idx].unreadCount + 1,
    );
    _chats
      ..removeAt(idx)
      ..insert(0, updated);
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || _nextPageUrl == null || _accessToken == null) return;
    _isLoadingMore = true;
    notifyListeners();

    final page = await _service.listChats(
      accessToken: _accessToken!,
      pageUrl: _nextPageUrl,
    );
    _chats.addAll(page.results);
    _nextPageUrl = page.next;

    _isLoadingMore = false;
    notifyListeners();
  }

  /// Archives (or unarchives) a chat and removes it from the currently
  /// loaded list immediately — this list only ever shows one side of the
  /// `?archived=` split, so a successful toggle always means "no longer
  /// belongs here".
  Future<bool> setArchived(int chatId, bool archived) async {
    if (_accessToken == null) return false;
    final success = archived
        ? await _service.archiveChat(accessToken: _accessToken!, chatId: chatId)
        : await _service.unarchiveChat(accessToken: _accessToken!, chatId: chatId);
    if (success) {
      _chats.removeWhere((c) => c.id == chatId);
      notifyListeners();
    }
    return success;
  }

  bool get isArchivedView => _archived;
}
