import 'dart:convert';

import 'package:backend/repositories/sheets_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('falls back to per-class restore after gateway 404', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      final action = (jsonDecode(request.body) as Map)['action'];
      if (requestCount <= 3) {
        return http.Response('Not Found', 404);
      }
      if (action == 'listSchedules') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {
                'classId': 'PRM393_SE1917_FA26',
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'classOffering': {'classId': 'PRM393_SE1917_FA26'},
            'students': const [],
            'lessons': const [],
          },
        }),
        200,
      );
    });

    final schedules = await SheetsRepository(
      gatewayUrl: 'https://example.test/exec',
      client: client,
    ).getAllSchedules();

    expect(schedules, hasLength(1));
    expect(requestCount, 5);
    expect(schedules.single['classOffering']['classId'], 'PRM393_SE1917_FA26');
  });

  test('falls back after an aggregate gateway error response', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      final action = (jsonDecode(request.body) as Map)['action'];
      if (requestCount == 1) {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'Data Gateway không trả toàn bộ lịch.',
          }),
          200,
        );
      }
      if (action == 'listSchedules') {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [
              {'classId': 'PRM393_SE1917_FA26'},
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'classOffering': {'classId': 'PRM393_SE1917_FA26'},
            'students': const [],
            'lessons': const [],
          },
        }),
        200,
      );
    });

    final schedules = await SheetsRepository(
      gatewayUrl: 'https://example.test/exec',
      client: client,
    ).getAllSchedules();

    expect(schedules, hasLength(1));
    expect(requestCount, greaterThanOrEqualTo(3));
  });
}
