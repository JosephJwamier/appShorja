import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Thrown when a request never reached the server because the device has no
/// network path — distinct from the server responding with an error, so
/// callers can show "no internet" instead of a generic failure message.
class NoConnectionException implements Exception {
  const NoConnectionException();
  @override
  String toString() => 'لا يوجد اتصال بالإنترنت';
}

/// Thrown when the access token is invalid and a silent refresh also failed
/// (or there was no refresh token to try) — the caller should treat this as
/// "the session is gone", not a normal request error.
class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'الجلسة منتهية، سجّل دخولاً من جديد';
}

/// Central HTTP client for every backend call. Attaches the bearer token,
/// and on a 401 tries exactly one silent token refresh before retrying the
/// original request — so a request made near the end of the access token's
/// lifetime no longer surfaces as a user-facing "session expired" error.
///
/// Deliberately has no dependency on `AuthProvider` (`services/` doesn't
/// import `providers/`) — [configure] is called once from AuthProvider's
/// constructor to wire the two together via plain callbacks instead.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? Function()? _getAccessToken;
  String? Function()? _getRefreshToken;
  void Function(String access, String refresh)? _onTokensRefreshed;
  Future<void> Function()? _onSessionExpired;

  void configure({
    required String? Function() getAccessToken,
    required String? Function() getRefreshToken,
    required void Function(String access, String refresh) onTokensRefreshed,
    required Future<void> Function() onSessionExpired,
  }) {
    _getAccessToken = getAccessToken;
    _getRefreshToken = getRefreshToken;
    _onTokensRefreshed = onTokensRefreshed;
    _onSessionExpired = onSessionExpired;
  }

  /// يعتمد زوج توكنات أصدره الخادم خارج مسار التحديث — حين يغيّر المستخدم
  /// كلمة المرور يُبطل الخادم كل توكنات التحديث القديمة ويعطي هذا الجهاز
  /// زوجاً جديداً، فإن لم يُحفظ خرج المستخدم من جهازه نفسه بعد دقائق.
  void adoptTokens(String access, String refresh) =>
      _onTokensRefreshed?.call(access, refresh);

  Future<http.Response> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<http.Response> post(String path, {Object? body, bool auth = true}) =>
      _send('POST', path, body: body, auth: auth);

  Future<http.Response> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<http.Response> put(String path, {Object? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<http.Response> delete(String path, {Object? body, bool auth = true}) =>
      _send('DELETE', path, body: body, auth: auth);

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final response = await _sendOnce(method, path, body: body, auth: auth);
    if (response.statusCode != 401 || !auth) return response;

    final refreshed = await _refresh();
    if (!refreshed) {
      await _onSessionExpired?.call();
      throw const SessionExpiredException();
    }
    return _sendOnce(method, path, body: body, auth: auth);
  }

  /// رفع صور وحقول معاً، بما في بقية الطلبات من تجديد للجلسة ومهلة.
  ///
  /// كانت هذه الطلبات تُرسل برمز قديم حملته الشاشة منذ فُتحت: من ملأ نموذج
  /// منتج في أكثر من نصف ساعة رُفض نشره. ولأن الطلب المُرسَل لا يُعاد إرساله
  /// تُقرأ ملفّاته أوّلاً ويُبنى من جديد لكل محاولة. والإعادة عند 401 وحده:
  /// طلبٌ انقطعت شبكته قد يكون نُفِّذ.
  Future<http.StreamedResponse> sendMultipart(
      http.MultipartRequest request) async {
    final files = [
      for (final f in request.files)
        (
          field: f.field,
          name: f.filename,
          type: f.contentType,
          bytes: await f.finalize().toBytes(),
        ),
    ];

    Future<http.StreamedResponse> attempt() async {
      final copy = http.MultipartRequest(request.method, request.url)
        ..headers.addAll(request.headers)
        ..fields.addAll(request.fields)
        ..files.addAll([
          for (final f in files)
            http.MultipartFile.fromBytes(f.field, f.bytes,
                filename: f.name, contentType: f.type),
        ]);
      final token = _getAccessToken?.call() ?? '';
      if (token.isNotEmpty) copy.headers['Authorization'] = 'Bearer $token';
      try {
        return await copy.send().timeout(_uploadTimeout);
      } on SocketException {
        throw const NoConnectionException();
      } on TimeoutException {
        throw const NoConnectionException();
      }
    }

    final response = await attempt();
    if (response.statusCode != 401) return response;
    if (!await _refresh()) {
      await _onSessionExpired?.call();
      throw const SessionExpiredException();
    }
    return attempt();
  }

  static const _uploadTimeout = Duration(minutes: 3);

  Future<http.Response> _sendOnce(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    // DRF pagination hands back an absolute `next`/`previous` URL — accept
    // it as-is instead of forcing every caller to strip the host back off.
    final uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      // الترويسة تُرسل فقط حين يوجد رمز فعلي. 'Bearer ' فارغة ليست
      // «بلا مصادقة» — إنها ترويسة فاسدة، و DRF يردّ عليها 401 بدل أن
      // يعامل الطلب كزائر. ومنذ أن صار التصفّح مفتوحاً للضيوف، ذلك
      // يعني رفض كل قراءة عامة يُفترض أن تنجح.
      if (auth && (_getAccessToken?.call() ?? '').isNotEmpty)
        'Authorization': 'Bearer ${_getAccessToken!.call()}',
    };
    final encodedBody = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'GET':
          return await http.get(uri, headers: headers).timeout(_timeout);
        case 'POST':
          return await http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'PATCH':
          return await http
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'PUT':
          return await http
              .put(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        case 'DELETE':
          return await http
              .delete(uri, headers: headers, body: encodedBody)
              .timeout(_timeout);
        default:
          throw ArgumentError('Unsupported method: $method');
      }
    } on SocketException {
      throw const NoConnectionException();
    } on TimeoutException {
      throw const NoConnectionException();
    }
  }

  // Several requests can 401 at roughly the same moment (e.g. a screen that
  // fires off a few parallel GETs right as the token expires) — this makes
  // sure they trigger exactly one refresh call instead of a stampede that
  // could each try to rotate the same refresh token.
  /// بلا مهلة كان الطلب على شبكة ميتة ينتظر إلى الأبد والشاشة تدور.
  static const _timeout = Duration(seconds: 45);

  Future<bool>? _refreshInFlight;

  Future<bool> _refresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refreshToken = _getRefreshToken?.call();
    if (refreshToken == null) return false;
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      ).timeout(_timeout);
      // الرفض الصريح وحده يُنهي الجلسة. خادمٌ يُعاد تشغيله (502) أو مزدحم
      // (429) أو شبكة منقطعة لا تعني أن الجلسة انتهت، وإخراج المستخدم
      // حينها كان يُخرج كل من صادف تجديده لحظة نشر تحديث.
      if (response.statusCode == 400 || response.statusCode == 401) {
        return false;
      }
      if (response.statusCode != 200) throw const NoConnectionException();
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newAccess = data['access'] as String?;
      if (newAccess == null) return false;
      // SIMPLE_JWT's ROTATE_REFRESH_TOKENS=True means a fresh refresh token
      // comes back too; the old one is blacklisted server-side the moment
      // this response lands.
      final newRefresh = data['refresh'] as String? ?? refreshToken;
      _onTokensRefreshed?.call(newAccess, newRefresh);
      return true;
    } on SocketException {
      throw const NoConnectionException();
    } on TimeoutException {
      throw const NoConnectionException();
    } on http.ClientException {
      throw const NoConnectionException();
    }
  }
}
