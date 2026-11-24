import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/services/api_client.dart';

Future<({bool signedOut, Object? error})> _run(
    Future<http.Response> Function() refresh) async {
  var signedOut = false;
  Object? error;
  ApiClient.instance.configure(
    getAccessToken: () => 'old',
    getRefreshToken: () => 'r',
    onTokensRefreshed: (_, _) {},
    onSessionExpired: () async => signedOut = true,
  );
  await http.runWithClient(() async {
    try {
      await ApiClient.instance.get('/wallet/me/');
    } catch (e) {
      error = e;
    }
  },
      () => MockClient((r) async => r.url.path.contains('refresh')
          ? await refresh()
          : http.Response('', 401)));
  return (signedOut: signedOut, error: error);
}

void main() {
  final outages = <String, Future<http.Response> Function()>{
    'a server restart': () async => http.Response('', 502),
    'throttling': () async => http.Response('', 429),
    'no network': () async => throw const SocketException('offline'),
    'a dropped connection': () async => throw http.ClientException('reset'),
  };
  outages.forEach((name, refresh) {
    test('$name during a token refresh does not sign the user out', () async {
      final r = await _run(refresh);
      expect(r.signedOut, isFalse);
      expect(r.error, isA<NoConnectionException>());
    });
  });

  test('a refused refresh token ends the session', () async {
    final r = await _run(() async => http.Response('', 401));
    expect(r.signedOut, isTrue);
    expect(r.error, isA<SessionExpiredException>());
  });
}
