import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/live_session.dart';
import '../models/live_comment.dart';
import '../config/api_config.dart';
import 'api_client.dart';

/// Talks to the Django backend's live-shopping endpoints
/// (/api/live-sessions/...). Video/audio itself is carried entirely by
/// Agora — this service only handles discovery, session lifecycle,
/// product queue/show, reservation, likes, and comments. Real-time fan-out
/// (viewer count, now-showing changes, new reservations/comments) arrives
/// over the ws/live/ socket for a session, connected directly by the screens (see
/// LiveBroadcastScreen/LiveViewerScreen), same pattern as the existing
/// auction/chat WebSocket screens.
class LiveSessionService {
  static const String baseUrl = ApiConfig.baseUrl;
  final _client = ApiClient.instance;

  Future<({List<LiveSession> sessions, bool hasMore})> fetchLiveSessions({
    required String accessToken,
    String ordering = '-current_viewer_count',
    String? status,
    int page = 1,
  }) async {
    final queryParams = <String, String>{
      'ordering': ordering,
      'page': page.toString(),
    };
    if (status != null && status.isNotEmpty) queryParams['status'] = status;

    final response = await _client
        .get('/live-sessions/?${Uri(queryParameters: queryParams).query}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return (
        sessions: results
            .map((e) => LiveSession.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: data['next'] != null,
      );
    }
    throw Exception('فشل جلب البثوث المباشرة');
  }

  Future<LiveSession> fetchLiveSessionDetail({
    required String accessToken,
    required int sessionId,
  }) async {
    final response = await _client.get('/live-sessions/$sessionId/');
    if (response.statusCode == 200) {
      return LiveSession.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception('فشل جلب تفاصيل البث');
  }

  /// The current user's own sessions (any status) — used to detect an
  /// already-live session so the owner can resume its control screen
  /// instead of accidentally starting a second one.
  Future<List<LiveSession>> fetchMySessions({required String accessToken}) async {
    final response = await _client.get('/live-sessions/my_sessions/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>;
      return results.map((e) => LiveSession.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('فشل جلب بثوثك');
  }

  Future<({bool success, String message, LiveSession? session})> createLiveSession({
    required String accessToken,
    required String title,
    String description = '',
    required bool startImmediately,
  }) async {
    final response = await _client.post(
      '/live-sessions/',
      body: {
        'title': title,
        'description': description,
        'start_immediately': startImmediately,
      },
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = response.statusCode == 201 && (body['success'] as bool? ?? false);
      return (
        success: success,
        message: body['message'] as String? ?? (success ? 'تم إنشاء البث' : 'فشل إنشاء البث'),
        session: success ? LiveSession.fromJson(body['data'] as Map<String, dynamic>) : null,
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم', session: null);
    }
  }

  Future<({bool success, String message, LiveSession? session})> _postAction({
    required String accessToken,
    required int sessionId,
    required String path,
  }) async {
    final response = await _client.post('/live-sessions/$sessionId/$path/');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = response.statusCode == 200 && (body['success'] as bool? ?? false);
      return (
        success: success,
        message: body['message'] as String? ?? '',
        session: (success && body['data'] != null)
            ? LiveSession.fromJson(body['data'] as Map<String, dynamic>)
            : null,
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم', session: null);
    }
  }

  Future<({bool success, String message, LiveSession? session})> goLive({
    required String accessToken,
    required int sessionId,
  }) =>
      _postAction(accessToken: accessToken, sessionId: sessionId, path: 'go_live');

  Future<({bool success, String message, LiveSession? session})> endSession({
    required String accessToken,
    required int sessionId,
  }) =>
      _postAction(accessToken: accessToken, sessionId: sessionId, path: 'end-session');

  Future<({bool success, String message, LiveSession? session})> cancelSession({
    required String accessToken,
    required int sessionId,
  }) =>
      _postAction(accessToken: accessToken, sessionId: sessionId, path: 'cancel-session');

  /// role: 'publisher' (store owner going live) or 'subscriber' (viewer).
  Future<LiveJoinToken> fetchJoinToken({
    required String accessToken,
    required int sessionId,
    required String role,
    int uid = 0,
  }) async {
    final response = await _client.post(
      '/live-sessions/$sessionId/join-token/',
      body: {'role': role, 'uid': uid},
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return LiveJoinToken.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw Exception('تعذّر الحصول على رمز الانضمام للبث');
  }

  Future<List<LiveCatalogEntry>> fetchCatalog({
    required String accessToken,
    required int sessionId,
  }) async {
    final response = await _client.get('/live-sessions/$sessionId/catalog/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['data'] as List<dynamic>;
      return results
          .map((e) => LiveCatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('فشل جلب منتجاتك');
  }

  /// One-tap show for an item already in the owner's catalog — price/deposit
  /// are pulled automatically from its listing unless overridden.
  Future<({bool success, String message})> showItem({
    required String accessToken,
    required int sessionId,
    required int itemId,
    double? price,
    double? depositAmount,
  }) async {
    final response = await _client.post(
      '/live-sessions/$sessionId/show-item/',
      body: {
        'item_id': itemId,
        'price': ?price,
        'deposit_amount': ?depositAmount,
      },
    );
    return _parseSuccessMessage(response);
  }

  /// Show a product that was never added to the app before — creates a
  /// minimal backing Item automatically, no separate "add product" step.
  Future<({bool success, String message})> quickShow({
    required String accessToken,
    required int sessionId,
    required String title,
    required double price,
    required double depositAmount,
    int quantity = 1,
  }) async {
    final response = await _client.post(
      '/live-sessions/$sessionId/quick-show/',
      body: {
        'title': title,
        'price': price,
        'deposit_amount': depositAmount,
        'quantity': quantity,
      },
    );
    return _parseSuccessMessage(response);
  }

  /// Starts a 2-minute live auction — same one-tap spirit as quickShow, but
  /// viewers bid (via AuctionService.placeBid) instead of instantly
  /// reserving. Settlement is the exact same auction machinery as any other
  /// auction; only the resulting winner Reservation and the live broadcast
  /// overlay are specific to being started from a live session.
  Future<({bool success, String message, LiveAuction? auction})> quickAuction({
    required String accessToken,
    required int sessionId,
    required String title,
    required double startingPrice,
    required double minimumIncrement,
    required double bidDeposit,
    int quantity = 1,
  }) async {
    final response = await _client.post(
      '/live-sessions/$sessionId/quick-auction/',
      body: {
        'title': title,
        'starting_price': startingPrice,
        'minimum_increment': minimumIncrement,
        'bid_deposit': bidDeposit,
        'quantity': quantity,
      },
    );

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = response.statusCode == 201 && (body['success'] as bool? ?? false);
      return (
        success: success,
        message: body['message'] as String? ?? (success ? 'تم بدء المزاد' : 'فشل بدء المزاد'),
        auction: success ? LiveAuction.fromJson(body['data'] as Map<String, dynamic>) : null,
      );
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم', auction: null);
    }
  }

  // Multipart image upload — kept on the raw http client directly (see
  // note in review_service.dart for why).

  /// Reserve the item currently 'now showing' — deposit is charged
  /// immediately, and [screenshotBytes] (captured from the live video frame
  /// on the viewer's device, always PNG) is attached as dispute-resolution
  /// evidence. Takes raw bytes rather than an XFile so there's no risk of
  /// double-reading a wrapper whose name/mimeType metadata isn't guaranteed
  /// to propagate into the multipart part Django expects as a real file.
  Future<({bool success, String message})> reserveItem({
    required String accessToken,
    required int sessionId,
    required int queueItemId,
    required int quantity,
    required Uint8List screenshotBytes,
    int? deliveryLocationId,
  }) async {
    final uri = Uri.parse('$baseUrl/live-sessions/$sessionId/reserve/');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.fields['queue_item_id'] = queueItemId.toString();
    request.fields['quantity'] = quantity.toString();
    if (deliveryLocationId != null) {
      request.fields['delivery_location_id'] = deliveryLocationId.toString();
    }

    request.files.add(http.MultipartFile.fromBytes(
      'screenshot',
      screenshotBytes,
      filename: 'live_reservation_${DateTime.now().millisecondsSinceEpoch}.png',
      contentType: MediaType('image', 'png'),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _parseSuccessMessage(response);
  }

  Future<({bool success, int likesCount})> likeSession({
    required String accessToken,
    required int sessionId,
  }) =>
      _postLike(accessToken: accessToken, sessionId: sessionId, path: 'like');

  Future<({bool success, int likesCount})> unlikeSession({
    required String accessToken,
    required int sessionId,
  }) =>
      _postLike(accessToken: accessToken, sessionId: sessionId, path: 'unlike');

  Future<({bool success, int likesCount})> _postLike({
    required String accessToken,
    required int sessionId,
    required String path,
  }) async {
    final response = await _client.post('/live-sessions/$sessionId/$path/');
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        success: response.statusCode == 200 && (body['success'] as bool? ?? false),
        likesCount: body['likes_count'] as int? ?? 0,
      );
    } catch (_) {
      return (success: false, likesCount: 0);
    }
  }

  Future<List<LiveComment>> fetchComments({
    required String accessToken,
    required int sessionId,
  }) async {
    final response = await _client.get('/live-sessions/$sessionId/comments/');
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = body['data'] as List<dynamic>;
      return results
          .map((e) => LiveComment.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('فشل جلب التعليقات');
  }

  Future<({bool success, String message})> postComment({
    required String accessToken,
    required int sessionId,
    required String content,
  }) async {
    final response = await _client.post(
      '/live-sessions/$sessionId/comments/',
      body: {'content': content},
    );
    return _parseSuccessMessage(response);
  }

  Future<({bool success, String message})> deleteComment({
    required String accessToken,
    required int sessionId,
    required int commentId,
  }) async {
    final response = await _client.delete('/live-sessions/$sessionId/comments/$commentId/');
    return _parseSuccessMessage(response);
  }

  ({bool success, String message}) _parseSuccessMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = (response.statusCode == 200 || response.statusCode == 201) &&
          (body['success'] as bool? ?? false);

      // Prefer the field-level validation detail over the generic top-level
      // 'message' (e.g. "Validation failed") when present — it's what
      // actually explains why a request was rejected.
      final errorsDetail = _formatErrors(body['errors']);
      final message = errorsDetail ??
          body['message'] as String? ??
          (success ? 'تم بنجاح' : 'فشلت العملية');
      return (success: success, message: message);
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  String? _formatErrors(dynamic errors) {
    if (errors is Map && errors.isNotEmpty) {
      return errors.entries.map((e) {
        final value = e.value is List ? (e.value as List).join('، ') : e.value.toString();
        return '${e.key}: $value';
      }).join(' — ');
    }
    if (errors is String && errors.isNotEmpty) return errors;
    return null;
  }
}
