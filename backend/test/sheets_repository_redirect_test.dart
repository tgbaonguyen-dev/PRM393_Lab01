import 'dart:convert';

import 'package:backend/repositories/sheets_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('follows Apps Script redirect with GET after the POST', () async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);

      if (request.url.host == 'gateway.test') {
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'getActiveWindow');
        return http.Response('', 302, headers: {
          'location': 'https://echo.test/result',
        });
      }

      expect(request.url.host, 'echo.test');
      expect(request.method, 'GET');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {'isOpen': true}
        }),
        200,
      );
    });

    final window = await SheetsRepository(
      gatewayUrl: 'https://gateway.test/exec',
      client: client,
    ).getActiveWindow('session-1');

    expect(window, {'isOpen': true});
    expect(methods, ['POST', 'GET']);
  });
}
