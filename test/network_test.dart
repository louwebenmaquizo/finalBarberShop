import 'dart:async';

import 'package:barber/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late int notices;

  setUp(() {
    notices = 0;
    TimeoutHttpClient.onConnectionProblem = () => notices++;
  });
  tearDown(() => TimeoutHttpClient.onConnectionProblem = null);

  Future<Object?> send(TimeoutHttpClient client) async {
    try {
      await client.get(Uri.parse('https://example.test/rest/v1/x'));
      return null;
    } catch (e) {
      return e;
    }
  }

  test('no connection is reported and still fails the request', () async {
    final client = TimeoutHttpClient(
      inner: MockClient((_) async => throw http.ClientException('Failed host lookup')),
    );
    expect(await send(client), isA<http.ClientException>());
    expect(notices, 1);
  });

  test('a request that never answers times out and is reported', () async {
    final client = TimeoutHttpClient(
      timeout: const Duration(milliseconds: 50),
      inner: MockClient((_) => Completer<http.Response>().future),
    );
    expect(await send(client), isA<TimeoutException>());
    expect(notices, 1);
  });

  test('server errors are not treated as connection problems', () async {
    final client = TimeoutHttpClient(
      inner: MockClient((_) async => http.Response('{"message":"boom"}', 500)),
    );
    expect(await send(client), isNull);
    expect(notices, 0);
  });
}
