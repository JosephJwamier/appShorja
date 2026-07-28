/// Models for the in-app store chat (التواصل مع المتجر).
/// Chat creation/lookup and history load go through the Django REST API;
/// live messages are pushed over the WebSocket (see StoreChatScreen).
library;

import '../utils/formatters.dart';
import 'product.dart';

class ChatMessage {
  final int id;
  final int? senderId;
  final String senderName;
  final String content;
  final String messageType;
  final String? attachmentUrl;
  final bool isRead;
  final DateTime createdAt;
  final double? offerAmount;
  final int? offerQuantity;
  final String? offerStatus;
  final bool isRedeemed;
  final bool isPending;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    required this.attachmentUrl,
    required this.isRead,
    required this.createdAt,
    this.offerAmount,
    this.offerQuantity,
    this.offerStatus,
    this.isRedeemed = false,
    this.isPending = false,
  });

  bool get isOffer => messageType == 'offer' || messageType == 'counter_offer';

  /// Optimistic local echo of a message this device just sent, inserted the
  /// instant the user hits send instead of waiting for it to round-trip
  /// through the server and back over the websocket — see StoreChatScreen._send.
  factory ChatMessage.pending({
    required int id,
    required int? senderId,
    required String content,
  }) =>
      ChatMessage(
        id: id,
        senderId: senderId,
        senderName: '',
        content: content,
        messageType: 'user',
        attachmentUrl: null,
        isRead: false,
        createdAt: DateTime.now(),
        isPending: true,
      );

  ChatMessage copyWith({String? offerStatus, bool? isRedeemed, bool? isRead}) =>
      ChatMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        content: content,
        messageType: messageType,
        attachmentUrl: attachmentUrl,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        offerAmount: offerAmount,
        offerQuantity: offerQuantity,
        offerStatus: offerStatus ?? this.offerStatus,
        isRedeemed: isRedeemed ?? this.isRedeemed,
        isPending: isPending,
      );

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// REST shape (MessageSerializer) — used for initial history load.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    return ChatMessage(
      id: json['id'] as int,
      senderId: sender is Map ? sender['id'] as int? : null,
      senderName: json['sender_name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'user',
      attachmentUrl: json['attachment_url'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      offerAmount: _toDoubleOrNull(json['offer_amount']),
      offerQuantity: json['offer_quantity'] as int?,
      offerStatus: json['offer_status'] as String?,
      isRedeemed: json['is_redeemed'] as bool? ?? false,
    );
  }

  /// WebSocket broadcast shape (ChatConsumer.chat_message) — used for live messages.
  factory ChatMessage.fromWsEvent(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['message_id'] as int,
      senderId: json['sender_id'] as int?,
      senderName: json['sender'] as String? ?? '',
      content: json['message'] as String? ?? '',
      messageType: json['message_type'] as String? ?? 'user',
      attachmentUrl: json['attachment_url'] as String?,
      isRead: false,
      createdAt:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      offerAmount: _toDoubleOrNull(json['offer_amount']),
      offerQuantity: json['offer_quantity'] as int?,
      offerStatus: json['offer_status'] as String?,
    );
  }
}

/// One row in the conversations inbox (GET /chats/) — distinct from
/// [ChatConversation], which is a single open thread with full history.
class ChatSummary {
  final int id;
  final int? otherUserId;
  final String otherUserName;
  final int? storeId;
  final String? storeName;
  final String? storeLogoUrl;
  final String? itemTitle;
  final String? itemThumbnailUrl;
  final String? lastMessageContent;
  final String? lastMessageType;
  final DateTime? lastMessageAt;
  final bool lastMessageIsRead;
  final int unreadCount;
  final bool isArchived;
  final bool isSupport;
  final bool isOwnStore;

  ChatSummary({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.storeId,
    required this.storeName,
    required this.storeLogoUrl,
    required this.itemTitle,
    required this.itemThumbnailUrl,
    required this.lastMessageContent,
    required this.lastMessageType,
    required this.lastMessageAt,
    required this.lastMessageIsRead,
    required this.unreadCount,
    required this.isArchived,
    required this.isSupport,
    required this.isOwnStore,
  });

  /// Person-first identity: "التواصل مع الدعم" for the fixed support chat;
  /// for a store-level chat, the *store's* name when viewed as the
  /// customer, but the *customer's* name when viewed as the store owner
  /// (`isOwnStore`) — otherwise a store owner's inbox would show their own
  /// store's name instead of who they're actually talking to. Falls back
  /// to the other participant's name for item-based chats (no store).
  String get displayTitle {
    if (isSupport) return 'التواصل مع الدعم';
    if (isOwnStore) return otherUserName;
    return storeName ?? otherUserName;
  }

  /// Store logo for a store chat viewed as the customer, else the item's
  /// thumbnail (there is no per-user profile photo in this system), else
  /// null (falls back to an initial-letter/icon avatar in the UI).
  String? get displayAvatarUrl {
    if (isSupport || isOwnStore) return null;
    return storeLogoUrl ?? itemThumbnailUrl;
  }

  /// Used by [ChatsProvider] to patch a tile in place from an FCM push
  /// payload (new last message + bumped unread count) without a network
  /// round-trip — see ChatsProvider.handleIncomingMessagePush.
  ChatSummary copyWith({
    String? lastMessageContent,
    String? lastMessageType,
    DateTime? lastMessageAt,
    bool? lastMessageIsRead,
    int? unreadCount,
  }) =>
      ChatSummary(
        id: id,
        otherUserId: otherUserId,
        otherUserName: otherUserName,
        storeId: storeId,
        storeName: storeName,
        storeLogoUrl: storeLogoUrl,
        itemTitle: itemTitle,
        itemThumbnailUrl: itemThumbnailUrl,
        lastMessageContent: lastMessageContent ?? this.lastMessageContent,
        lastMessageType: lastMessageType ?? this.lastMessageType,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastMessageIsRead: lastMessageIsRead ?? this.lastMessageIsRead,
        unreadCount: unreadCount ?? this.unreadCount,
        isArchived: isArchived,
        isSupport: isSupport,
        isOwnStore: isOwnStore,
      );

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    final other = json['other_user'];
    final store = json['store'];
    final item = json['item'];
    final latest = json['latest_message'];
    final itemImages = item is Map ? item['images'] as List<dynamic>? : null;
    final firstItemImage = (itemImages != null && itemImages.isNotEmpty)
        ? itemImages.first as Map<String, dynamic>?
        : null;
    final rawThumbnail = firstItemImage != null
        ? fixMediaUrl(firstItemImage['image'] as String?)
        : null;
    return ChatSummary(
      id: json['id'] as int,
      otherUserId: other is Map ? other['id'] as int? : null,
      otherUserName: other is Map ? (other['username'] as String? ?? '') : '',
      storeId: store is Map ? store['id'] as int? : null,
      storeName: store is Map ? store['name'] as String? : null,
      storeLogoUrl: store is Map ? store['logo_url'] as String? : null,
      itemTitle: item is Map ? item['title'] as String? : null,
      itemThumbnailUrl:
          (rawThumbnail != null && rawThumbnail.isNotEmpty) ? rawThumbnail : null,
      lastMessageContent: latest is Map ? latest['content'] as String? : null,
      lastMessageType: latest is Map ? latest['type'] as String? : null,
      lastMessageAt: latest is Map
          ? DateTime.tryParse(latest['created_at'] as String? ?? '')
          : null,
      lastMessageIsRead: latest is Map ? (latest['is_read'] as bool? ?? true) : true,
      unreadCount: json['unread_count'] as int? ?? 0,
      isArchived: json['is_archived'] as bool? ?? false,
      isSupport: json['is_support'] as bool? ?? false,
      isOwnStore: json['is_own_store'] as bool? ?? false,
    );
  }
}

class ChatConversation {
  final int id;
  final int? otherUserId;
  final String otherUserName;
  final List<ChatMessage> messages;
  final Product? item;
  final bool hasMoreMessages;
  final String? storeName;
  final String? storeLogoUrl;
  final bool isSupport;
  final bool isOwnStore;

  ChatConversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    required this.messages,
    this.item,
    this.hasMoreMessages = false,
    this.storeName,
    this.storeLogoUrl,
    this.isSupport = false,
    this.isOwnStore = false,
  });

  /// Same person-first identity rule as [ChatSummary.displayTitle] — kept
  /// here too so a chat opened directly by id (e.g. from a push
  /// notification, with no title passed in) still gets it right instead of
  /// falling back to a blank title.
  String get displayTitle {
    if (isSupport) return 'التواصل مع الدعم';
    if (isOwnStore) return otherUserName;
    return storeName ?? otherUserName;
  }

  String? get displayAvatarUrl {
    if (isSupport || isOwnStore) return null;
    return storeLogoUrl ?? item?.firstImage;
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final other = json['other_user'];
    final item = json['item'];
    final store = json['store'];
    final rawMessages = (json['messages'] as List<dynamic>?) ?? [];
    return ChatConversation(
      id: json['id'] as int,
      otherUserId: other is Map ? other['id'] as int? : null,
      otherUserName: other is Map ? (other['username'] as String? ?? '') : '',
      messages: rawMessages
          .cast<Map<String, dynamic>>()
          .map((e) => ChatMessage.fromJson(e))
          .toList(),
      item: item is Map<String, dynamic> ? Product.fromJson(item) : null,
      hasMoreMessages: json['has_more_messages'] as bool? ?? false,
      storeName: store is Map ? store['name'] as String? : null,
      storeLogoUrl: store is Map ? store['logo_url'] as String? : null,
      isSupport: json['is_support'] as bool? ?? false,
      isOwnStore: json['is_own_store'] as bool? ?? false,
    );
  }
}
