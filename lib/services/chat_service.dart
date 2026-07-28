import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat.dart';
import '../config/api_config.dart';
import 'api_client.dart';

const _imageExtensionToSubtype = {
  'jpg': 'jpeg',
  'jpeg': 'jpeg',
  'png': 'png',
  'webp': 'webp',
  'gif': 'gif',
  'heic': 'heic',
};

/// Resolves the real content type for a picked image so the backend's
/// image-only validation (which checks the upload's content type) accepts
/// it — without this, MultipartFile defaults to application/octet-stream.
MediaType _imageMediaType(XFile file) {
  final mime = file.mimeType;
  if (mime != null && mime.startsWith('image/')) {
    final subtype = mime.split('/').last;
    return MediaType('image', subtype);
  }
  final ext = file.name.split('.').last.toLowerCase();
  return MediaType('image', _imageExtensionToSubtype[ext] ?? 'jpeg');
}

/// Talks to the Django chat endpoints for store-level conversations.
/// Live message delivery goes over the WebSocket (see StoreChatScreen) —
/// this service only handles chat creation/lookup, history load, and the
/// conversations list.
class ChatService {
  static const String baseUrl = ApiConfig.baseUrl;
  final _client = ApiClient.instance;

  /// Create (or fetch existing) direct chat with a store.
  Future<({bool success, String message, ChatConversation? chat})>
      createOrGetStoreChat({
    required String accessToken,
    required int storeId,
    String? initialMessage,
  }) async {
    final response = await _client.post(
      '/chats/create_or_get_store/',
      body: {
        'store_id': storeId,
        if (initialMessage != null && initialMessage.isNotEmpty)
          'initial_message': initialMessage,
      },
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      if (success && body['data'] != null) {
        return (
          success: true,
          message: body['message'] as String? ?? '',
          chat: ChatConversation.fromJson(body['data'] as Map<String, dynamic>),
        );
      }
      return (
        success: false,
        message: body['message'] as String? ?? 'تعذّر بدء المحادثة',
        chat: null,
      );
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        chat: null,
      );
    }
  }

  /// Create (or fetch existing) the current user's one support conversation
  /// (التواصل مع الدعم) — no id needed, there's exactly one fixed
  /// counterparty on the backend.
  Future<({bool success, String message, ChatConversation? chat})>
      createOrGetSupportChat({
    required String accessToken,
    String? initialMessage,
  }) async {
    final response = await _client.post(
      '/chats/create_or_get_support/',
      body: {
        if (initialMessage != null && initialMessage.isNotEmpty)
          'initial_message': initialMessage,
      },
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      if (success && body['data'] != null) {
        return (
          success: true,
          message: body['message'] as String? ?? '',
          chat: ChatConversation.fromJson(body['data'] as Map<String, dynamic>),
        );
      }
      return (
        success: false,
        message: body['message'] as String? ?? 'تعذّر فتح محادثة الدعم',
        chat: null,
      );
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        chat: null,
      );
    }
  }

  /// Create (or fetch existing) chat about a specific item.
  Future<({bool success, String message, ChatConversation? chat})>
      createOrGetChat({
    required String accessToken,
    required int itemId,
  }) async {
    final response = await _client.post(
      '/chats/create_or_get/',
      body: {'item_id': itemId},
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      if (success && body['data'] != null) {
        return (
          success: true,
          message: body['message'] as String? ?? '',
          chat: ChatConversation.fromJson(body['data'] as Map<String, dynamic>),
        );
      }
      return (
        success: false,
        message: body['message'] as String? ?? 'تعذّر بدء المحادثة',
        chat: null,
      );
    } catch (_) {
      return (
        success: false,
        message: 'استجابة غير متوقّعة من الخادم',
        chat: null,
      );
    }
  }

  /// Send a price offer for the chat's item — [offerAmount] is the total
  /// price for [quantity] items (not a per-unit price).
  Future<({bool success, String message})> sendOffer({
    required String accessToken,
    required int chatId,
    required double offerAmount,
    required int quantity,
    String message = '',
  }) async {
    final response = await _client.post(
      '/chats/$chatId/send_offer/',
      body: {
        'offer_amount': offerAmount,
        'quantity': quantity,
        'message': message,
      },
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      if (!success) {
        final errors = body['errors'];
        return (
          success: false,
          message: errors != null
              ? errors.toString()
              : (body['message'] as String? ?? 'تعذّر إرسال العرض'),
        );
      }
      return (success: true, message: body['message'] as String? ?? 'تم إرسال العرض');
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  Future<({bool success, String message})> acceptOffer({
    required String accessToken,
    required int messageId,
  }) =>
      _respondToOffer(
          accessToken: accessToken, messageId: messageId, action: 'accept_offer');

  Future<({bool success, String message})> rejectOffer({
    required String accessToken,
    required int messageId,
  }) =>
      _respondToOffer(
          accessToken: accessToken, messageId: messageId, action: 'reject_offer');

  Future<({bool success, String message})> _respondToOffer({
    required String accessToken,
    required int messageId,
    required String action,
  }) async {
    final response = await _client.post('/messages/$messageId/$action/');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      return (
        success: success,
        message: body['message'] as String? ?? (success ? '' : 'تعذّر تنفيذ الطلب'),
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  /// Delete one of the current user's own messages (sender-only, backend
  /// soft-deletes it as is_deleted_by_sender — see MessageViewSet.destroy).
  Future<({bool success, String message})> deleteMessage({
    required String accessToken,
    required int messageId,
  }) async {
    final response = await _client.delete('/messages/$messageId/');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      return (
        success: success,
        message: body['message'] as String? ?? (success ? '' : 'تعذّر حذف الرسالة'),
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  /// Fetch full chat with message history.
  Future<ChatConversation?> fetchChat({
    required String accessToken,
    required int chatId,
  }) async {
    final response = await _client.get('/chats/$chatId/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final data = (body is Map<String, dynamic> && body['data'] != null)
          ? body['data']
          : body;
      return ChatConversation.fromJson(data as Map<String, dynamic>);
    }
    return null;
  }

  /// Fetch the page of messages just before [beforeMessageId] — used when
  /// the user scrolls to the top of a long-running thread. `fetchChat`
  /// only ships the latest ~30 messages inline (see ChatDetailSerializer
  /// on the backend); this reaches further back.
  Future<({List<ChatMessage> results, bool hasMore})> fetchOlderMessages({
    required String accessToken,
    required int chatId,
    required int beforeMessageId,
  }) async {
    final response = await _client
        .get('/chats/$chatId/messages/?before=$beforeMessageId');

    if (response.statusCode != 200) return (results: <ChatMessage>[], hasMore: false);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['data'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
    return (results: results, hasMore: body['has_more'] as bool? ?? false);
  }

  /// List the current user's conversations (newest-updated first), one page
  /// at a time — the backend paginates this endpoint (PAGE_SIZE=20), so a
  /// user with more chats than that needs [pageUrl] (the previous page's
  /// `next`) to reach the rest. Same shape as StoreReviewService.fetchReviews.
  Future<({List<ChatSummary> results, String? next, int count})> listChats({
    required String accessToken,
    bool archived = false,
    String? pageUrl,
  }) async {
    final path = pageUrl ?? '/chats/?archived=$archived';
    final response = await _client.get(path);

    if (response.statusCode != 200) return (results: <ChatSummary>[], next: null, count: 0);

    final body = jsonDecode(response.body);
    final results = (body is Map<String, dynamic> ? body['results'] : body)
            as List<dynamic>? ??
        [];
    final chats = results
        .cast<Map<String, dynamic>>()
        .map((e) => ChatSummary.fromJson(e))
        .toList();
    return (
      results: chats,
      next: body is Map<String, dynamic> ? body['next'] as String? : null,
      count: body is Map<String, dynamic>
          ? (body['count'] as int? ?? chats.length)
          : chats.length,
    );
  }

  /// Hide a conversation from the main inbox without deleting it — it still
  /// reappears via `/chats/?archived=true`, and unarchives itself the next
  /// time either side starts a new chat with the same counterpart/item.
  Future<bool> archiveChat({required String accessToken, required int chatId}) =>
      _archiveAction(chatId: chatId, action: 'archive');

  Future<bool> unarchiveChat({required String accessToken, required int chatId}) =>
      _archiveAction(chatId: chatId, action: 'unarchive');

  Future<bool> _archiveAction({required int chatId, required String action}) async {
    final response = await _client.post('/chats/$chatId/$action/');
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  // Multipart image upload — kept on the raw http client directly (see
  // note in review_service.dart for why).

  /// Upload an image (with an optional caption) into a chat. The created
  /// message is not returned/inserted locally — it arrives back over the
  /// WebSocket the same way it does for every other participant, since the
  /// backend broadcasts it into the chat's group after saving it.
  Future<({bool success, String message})> sendImageMessage({
    required String accessToken,
    required int chatId,
    required XFile image,
    String caption = '',
  }) async {
    final uri = Uri.parse('$baseUrl/chats/$chatId/send_message/');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['content'] = caption;

    final bytes = await image.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'attachment',
        bytes,
        filename: image.name,
        contentType: _imageMediaType(image),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] as bool? ??
          (response.statusCode >= 200 && response.statusCode < 300);
      return (
        success: success,
        message: body['message'] as String? ?? (success ? '' : 'تعذّر إرسال الصورة'),
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }
}
