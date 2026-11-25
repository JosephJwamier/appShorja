import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marketplace_app/services/api_client.dart';

void main() {
  test('an upload carries the current token and ends a dead session',
      () async {
    // flutter_test stubs HttpClient; this one talks to a real local server.
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      final seen = <String>[];
      server.listen((r) async {
        final body = await utf8.decoder.bind(r).join();
        final token = r.headers.value('authorization') ?? '';
        seen.add('$token ${body.contains('hello')} ${body.contains('"title"')}');
        r.response.statusCode = token == 'Bearer new' ? 201 : 401;
        await r.response.close();
      });

      var access = 'old';
      ApiClient.instance.configure(
        getAccessToken: () => access,
        getRefreshToken: () => null,
        onTokensRefreshed: (a, _) => access = a,
        onSessionExpired: () async {},
      );
      http.MultipartRequest request() => http.MultipartRequest(
          'POST', Uri.parse('http://127.0.0.1:${server.port}/x'))
        ..fields['title'] = 't'
        ..files.add(http.MultipartFile.fromBytes(
            'images', utf8.encode('hello'),
            filename: 'a.txt'));

      // No refresh token: the session is over.
      await expectLater(ApiClient.instance.sendMultipart(request()),
          throwsA(isA<SessionExpiredException>()));
      expect(seen, ['Bearer old true true']);

      // The token of now, not the one the screen opened with.
      access = 'new';
      final r = await ApiClient.instance.sendMultipart(
          request()..headers['Authorization'] = 'Bearer stale');
      expect(r.statusCode, 201);
      expect(seen.last, 'Bearer new true true');
      await server.close(force: true);
    }, createHttpClient: (c) => _Real().createHttpClient(c));
  });
}

class _Real extends HttpOverrides {}
