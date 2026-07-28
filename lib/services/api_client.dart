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
      if (auth) 'Authorization': 'Bearer ${_getAccessToken?.call() ?? ''}',
    };
    final encodedBody = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'GET':
          return await http.get(uri, headers: headers);
        case 'POST':
          return await http.post(uri, headers: headers, body: encodedBody);
        case 'PATCH':
          return await http.patch(uri, headers: headers, body: encodedBody);
        case 'PUT':
          return await http.put(uri, headers: headers, body: encodedBody);
        case 'DELETE':
          return await http.delete(uri, headers: headers, body: encodedBody);
        default:
          throw ArgumentError('Unsupported method: $method');
      }
    } on SocketException {
      throw const NoConnectionException();
    }
  }

  // Several requests can 401 at roughly the same moment (e.g. a screen that
  // fires off a few parallel GETs right as the token expires) — this makes
  // sure they trigger exactly one refresh call instead of a stampede that
  // could each try to rotate the same refresh token.
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
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newAccess = data['access'] as String?;
      if (newAccess == null) return false;
      // SIMPLE_JWT's ROTATE_REFRESH_TOKENS=True means a fresh refresh token
      // comes back too; the old one is blacklisted server-side the moment
      // this response lands.
      final newRefresh = data['refresh'] as String? ?? refreshToken;
      _onTokensRefreshed?.call(newAccess, newRefresh);
      return true;
    } catch (_) {
      return false;
    }
  }
}
