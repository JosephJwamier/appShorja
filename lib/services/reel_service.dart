import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/reel.dart';
import 'api_client.dart';

/// Talks to the Django backend's Reels endpoints (/api/reels/...) — see the
/// "Reels" plan for the full contract. Two calls in this file deliberately
/// bypass [ApiClient]: the object-storage PUTs in [uploadBytesToS3]. Those
/// are direct uploads to a presigned URL (Cloudflare R2, S3-compatible —
/// hence the method name), not requests to our own backend at all,
/// and ApiClient's silent-refresh-and-retry only knows how to replay a
/// plain JSON body — it can't resend bytes that already streamed out over
/// the wire (same reasoning documented in item_service.dart for multipart
/// image uploads).
class ReelService {
  final _client = ApiClient.instance;

  /// Step 1 of the upload flow — creates a `Reel(status='pending_upload')`
  /// row server-side and returns presigned PUT URLs for the video (and,
  /// when [hasThumbnail] is true, the thumbnail). Returned as a raw map
  /// (not a model) since it's a one-shot upload handshake, not a resource
  /// this app renders anywhere.
  ///
  /// Response shape (per the reels API contract):
  /// {reel_id, video_upload_url, video_key, thumbnail_upload_url,
  ///  thumbnail_key, expires_in}
  Future<Map<String, dynamic>> requestUploadUrl({
    required String contentType,
    required bool hasThumbnail,
  }) async {
    final response = await _client.post(
      '/reels/request_upload_url/',
      body: {
        'content_type': contentType,
        'has_thumbnail': hasThumbnail,
      },
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      // Backend wraps the handshake payload in {success, data: {...}} —
      // unwrap so callers can read reel_id/video_upload_url/etc directly.
      return decoded['data'] as Map<String, dynamic>;
    }
    throw Exception(_extractErrorMessage(response, 'تعذّر بدء رفع الريل'));
  }

  /// Step 2 — uploads raw bytes directly to S3 via the presigned URL from
  /// [requestUploadUrl]. [contentType] MUST match exactly what was sent to
  /// request_upload_url, or S3 rejects the PUT with a signature mismatch.
  ///
  /// Two upload paths, chosen by whether [onProgress] is supplied:
  ///  - No callback: a single `http.put` — simplest option, used for the
  ///    thumbnail (small, uploads near-instantly, a progress bar would be
  ///    pointless).
  ///  - With callback: an `http.StreamedRequest` that feeds the body in
  ///    chunks so real upload progress can be reported — plain `http.put`
  ///    has no such hook. Used for the video PUT so create_reel_screen can
  ///    show an actual progress bar during the (potentially slow) upload.
  Future<void> uploadBytesToS3({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse(uploadUrl);

    if (onProgress == null) {
      final response = await http.put(
        uri,
        headers: {'Content-Type': contentType},
        body: bytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('فشل رفع الملف إلى التخزين [${response.statusCode}]');
      }
      return;
    }

    final request = http.StreamedRequest('PUT', uri);
    request.headers['Content-Type'] = contentType;
    request.contentLength = bytes.length;

    final total = bytes.length;
    const chunkSize = 64 * 1024;

    unawaited(() async {
      for (var offset = 0; offset < total; offset += chunkSize) {
        final end = (offset + chunkSize < total) ? offset + chunkSize : total;
        request.sink.add(bytes.sublist(offset, end));
        onProgress(end / total);
        // Yield a tick so the progress callback's setState can actually
        // paint before the next chunk is queued, instead of the whole
        // upload racing through in one synchronous burst.
        await Future.delayed(Duration.zero);
      }
      await request.sink.close();
    }());

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('فشل رفع الفيديو إلى التخزين [${response.statusCode}]');
    }
  }

  /// Step 3 — confirms the upload landed, moves it from `incoming/` to
  /// `reels/` server-side, and publishes it. Returns the full [Reel] with
  /// complete public video_url/thumbnail_url (Cloudflare R2 custom domain).
  Future<Reel> finalizeReel({
    required int reelId,
    required String caption,
    int? itemId,
    required int durationSeconds,
  }) async {
    final response = await _client.post(
      '/reels/$reelId/finalize/',
      body: {
        'caption': caption,
        'item_id': ?itemId,
        'duration_seconds': durationSeconds,
      },
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      // Backend wraps the published reel in {success, message, data: {...}}.
      return Reel.fromJson(decoded['data'] as Map<String, dynamic>);
    }
    throw Exception(_extractErrorMessage(response, 'فشل نشر الريل'));
  }

  /// Public feed — published reels only, newest first, standard DRF
  /// pagination (mirrors LiveSessionService.fetchLiveSessions' shape).
  Future<({List<Reel> reels, bool hasMore})> fetchFeed({
    required String accessToken,
    int page = 1,
  }) async {
    final response = await _client.get('/reels/?page=$page');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return (
        reels: results.map((e) => Reel.fromJson(e as Map<String, dynamic>)).toList(),
        hasMore: data['next'] != null,
      );
    }
    throw Exception('فشل جلب الريلز');
  }

  /// One store's reels — the grid on its public profile (`?store=<id>`).
  ///
  /// Same shape as [fetchFeed], and the same endpoint: the backend narrows
  /// by store and still returns published rows only, so an archived or
  /// half-uploaded reel never reaches a visitor. The owner's own view of
  /// these is [fetchMyReels], which is the one that shows every status.
  Future<({List<Reel> reels, bool hasMore})> fetchStoreReels({
    required String accessToken,
    required int storeId,
    int page = 1,
  }) async {
    final response = await _client.get('/reels/?store=$storeId&page=$page');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return (
        reels: results.map((e) => Reel.fromJson(e as Map<String, dynamic>)).toList(),
        hasMore: data['next'] != null,
      );
    }
    throw Exception('فشل جلب ريلزات المتجر');
  }

  /// The current store's own reels, any status (pending_upload/published/
  /// failed/archived) — for the owner's management screen.
  Future<List<Reel>> fetchMyReels({required String accessToken}) async {
    final response = await _client.get('/reels/my_reels/');
    if (response.statusCode == 200) {
      final list = _asList(jsonDecode(response.body));
      return list.map((e) => Reel.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('فشل جلب ريلزاتك');
  }

  Future<({bool success, int likesCount})> likeReel({
    required String accessToken,
    required int reelId,
  }) =>
      _postLike(reelId, 'like');

  Future<({bool success, int likesCount})> unlikeReel({
    required String accessToken,
    required int reelId,
  }) =>
      _postLike(reelId, 'unlike');

  Future<({bool success, int likesCount})> _postLike(int reelId, String path) async {
    final response = await _client.post('/reels/$reelId/$path/');
    final ok = response.statusCode == 200 || response.statusCode == 201;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (success: ok, likesCount: body['likes_count'] as int? ?? 0);
    } catch (_) {
      return (success: ok, likesCount: 0);
    }
  }

  /// يضيف الريل إلى مفضلة المشاهد أو يزيله منها.
  ///
  /// نداء واحد بمُعامل منطقي لا دالّتان كـ[likeReel]/[unlikeReel]: الزرّ
  /// تبديليّ ولم يُستدعَ أي اتجاه منه وحده في أي شاشة — نفس شكل
  /// [ItemService.setFavorite] للمنتجات.
  ///
  /// يُرجع حالة الخادم النهائية لا ما طُلب: حفظٌ مكرّر يردّ `is_saved=true`
  /// وإزالةُ ما لم يُحفظ تردّ `false`، وكلتاهما الحقيقة.
  Future<bool> setSaved({
    required String accessToken,
    required int reelId,
    required bool saved,
  }) async {
    final response =
        await _client.post('/reels/$reelId/${saved ? 'save' : 'unsave'}/');
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_extractErrorMessage(
          response,
          saved ? 'تعذّر حفظ الريل' : 'تعذّر إزالة الريل من المفضلة'));
    }
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['is_saved'] as bool? ?? saved;
    } catch (_) {
      return saved;
    }
  }

  /// مفضلة المشاهد من الريلز، الأحدث **حفظاً** أولاً — لا الأحدث نشراً.
  ///
  /// الخادم يُسقط ما لم يبقَ منشوراً (أرشفه صاحبه أو حُذف)، فقد تعود صفحة
  /// أقصر من حجمها. وهذا مقصود: إشارةٌ مرجعية تفتح على شاشة سوداء أسوأ من
  /// إشارةٍ اختفت.
  Future<({List<Reel> reels, bool hasMore})> fetchSavedReels({
    required String accessToken,
    int page = 1,
  }) async {
    final response = await _client.get('/reels/saved/?page=$page');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return (
        reels: results.map((e) => Reel.fromJson(e as Map<String, dynamic>)).toList(),
        hasMore: data['next'] != null,
      );
    }
    throw Exception('فشل جلب الريلز المحفوظة');
  }

  Future<List<ReelComment>> fetchComments({
    required String accessToken,
    required int reelId,
  }) async {
    final response = await _client.get('/reels/$reelId/comments/');
    if (response.statusCode == 200) {
      final list = _asList(jsonDecode(response.body));
      return list.map((e) => ReelComment.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('فشل جلب التعليقات');
  }

  Future<({bool success, String message})> postComment({
    required String accessToken,
    required int reelId,
    required String content,
  }) async {
    final response = await _client.post(
      '/reels/$reelId/comments/',
      body: {'content': content},
    );
    return _parseSuccessMessage(response);
  }

  Future<({bool success, String message})> deleteComment({
    required String accessToken,
    required int reelId,
    required int commentId,
  }) async {
    final response = await _client.delete('/reels/$reelId/comments/$commentId/');
    if (response.statusCode == 204 || response.statusCode == 200) {
      return (success: true, message: 'تم حذف التعليق');
    }
    return _parseSuccessMessage(response);
  }

  /// Fire-and-forget view tracking — swallows failures on purpose (a failed
  /// view ping should never surface an error to someone just scrolling the
  /// feed).
  Future<void> recordView({
    required String accessToken,
    required int reelId,
  }) async {
    try {
      await _client.post('/reels/$reelId/view/');
    } catch (_) {
      // best-effort only
    }
  }

  /// Owner edit — the only two things changeable after publishing: the
  /// caption and the tagged product. The video itself is immutable (its S3
  /// object is written once at finalize), so replacing a reel's video means
  /// deleting it and posting a new one.
  ///
  /// [itemId] is sent as an explicit `null` when [clearItem] is true — that's
  /// how the backend tells "remove the tag" apart from "leave it alone",
  /// since an omitted key means the latter.
  Future<({bool success, String message, Reel? reel})> updateReel({
    required String accessToken,
    required int reelId,
    required String caption,
    int? itemId,
    bool clearItem = false,
  }) async {
    final response = await _client.patch(
      '/reels/$reelId/',
      body: {
        'caption': caption,
        if (clearItem || itemId != null) 'item_id': itemId,
      },
    );
    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return (
          success: true,
          message: 'تم حفظ التعديلات',
          reel: Reel.fromJson(decoded),
        );
      } catch (_) {
        // Saved server-side; we just can't echo the fresh copy back.
        return (success: true, message: 'تم حفظ التعديلات', reel: null);
      }
    }
    final parsed = _parseSuccessMessage(response);
    return (success: false, message: parsed.message, reel: null);
  }

  /// PERMANENT delete — removes the row server-side *and* the video and
  /// thumbnail objects from S3. Deliberately not the archive/soft-delete the
  /// rest of this app uses: deleting your own reel means the video stops
  /// existing, not just stops being listed. A reel that has been reported is
  /// the one exception (the backend keeps an invisible tombstone row so the
  /// moderation trail survives) — indistinguishable from here, and gone from
  /// my_reels either way.
  ///
  /// A 204/200 with no parseable body still counts as success.
  Future<({bool success, String message})> deleteReel({
    required String accessToken,
    required int reelId,
  }) async {
    final response = await _client.delete('/reels/$reelId/');
    if (response.statusCode == 204 || response.statusCode == 200) {
      return (success: true, message: 'تم حذف الريل نهائياً');
    }
    return _parseSuccessMessage(response);
  }

  // ---- helpers -------------------------------------------------------

  /// Accepts a bare list, a DRF-paginated {results:[...]}, or the
  /// {data:[...]} envelope LiveSessionService's comments endpoint uses —
  /// the exact shape depends on details of the parallel backend
  /// implementation this UI is built against by contract, not by shared code.
  List<dynamic> _asList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      final v = decoded['results'] ?? decoded['data'];
      if (v is List) return v;
    }
    return const [];
  }

  ({bool success, String message}) _parseSuccessMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = (response.statusCode == 200 || response.statusCode == 201) &&
          (body['success'] as bool? ?? true);
      final errorsDetail = _formatErrors(body['errors']);
      final message = errorsDetail ??
          body['message'] as String? ??
          body['detail'] as String? ??
          (success ? 'تم بنجاح' : 'فشلت العملية');
      return (success: success, message: message);
    } catch (_) {
      final ok = response.statusCode == 200 || response.statusCode == 201;
      return (success: ok, message: ok ? 'تم بنجاح' : 'استجابة غير متوقّعة من الخادم');
    }
  }

  String _extractErrorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final detail = body['detail'] ?? body['message'];
        if (detail != null) return detail.toString();
        final errors = _formatErrors(body);
        if (errors != null) return errors;
      }
    } catch (_) {
      // fall through to fallback
    }
    return fallback;
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
