import 'dart:convert';

import 'package:backend/controllers/session_controller.dart';
import 'package:backend/repositories/sheets_repository.dart';
import 'package:backend/services/qr_service.dart';
import 'package:backend/services/session_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeSheetsRepo extends SheetsRepository {
  Map<String, dynamic>? activeWindow;

  _FakeSheetsRepo() : super(gatewayUrl: 'http://localhost');

  @override
  Future<Map<String, dynamic>?> openAttendanceWindow(String sessionId) async {
    activeWindow = {
      'windowId': 'win-123',
      'sessionId': sessionId,
      'openedAt': DateTime.now().toUtc().toIso8601String(),
      'isOpen': true,
    };
    return activeWindow;
  }

  @override
  Future<Map<String, dynamic>?> getActiveWindow(String sessionId) async {
    return activeWindow;
  }

  @override
  Future<bool> closeAttendanceWindow(String windowId) async {
    if (activeWindow != null && activeWindow!['windowId'] == windowId) {
      activeWindow!['isOpen'] = false;
      activeWindow!['closedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    return true;
  }
}

void main() {
  group('SessionController', () {
    late _FakeSheetsRepo fakeRepo;
    late SessionController controller;

    setUp(() {
      fakeRepo = _FakeSheetsRepo();
      controller = SessionController(
        sessionService: SessionService(repository: fakeRepo),
        qrService: QrService(secret: 'test-secret-key-32-chars-long-here'),
        checkInBaseUrl: 'http://localhost:3000/checkin',
      );
    });

    test('POST /session/open and POST /open succeed with valid params', () async {
      final res = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/session/open'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'sessionId': 'sess-1', 'classId': 'cls-1'}),
        ),
      );

      expect(res.statusCode, 200);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isTrue);
      expect(body['data']['windowId'], 'win-123');
      expect(body['data']['status'], 'open');
    });

    test('POST /open returns 400 for missing fields', () async {
      final res = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/open'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'sessionId': ''}),
        ),
      );

      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isFalse);
    });

    test('GET /session/qr returns 200 with QR URL when session is open', () async {
      // First open
      await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/session/open'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'sessionId': 'sess-1', 'classId': 'cls-1'}),
        ),
      );

      // Request QR
      final qrRes = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/session/qr?sessionId=sess-1&classId=cls-1'),
        ),
      );

      expect(qrRes.statusCode, 200);
      final body = jsonDecode(await qrRes.readAsString());
      expect(body['success'], isTrue);
      expect(body['data']['qrUrl'], contains('http://localhost:3000/checkin'));
      expect(body['data']['qrToken'], isNotEmpty);
      expect(body['data']['expiresAt'], isA<int>());
    });

    test('GET /session/qr returns 409 when session is not open', () async {
      final qrRes = await controller.router.call(
        Request(
          'GET',
          Uri.parse('http://localhost/session/qr?sessionId=sess-none&classId=cls-none'),
        ),
      );

      expect(qrRes.statusCode, 409);
      final body = jsonDecode(await qrRes.readAsString());
      expect(body['status'], 'SESSION_CLOSED');
    });

    test('POST /session/close succeeds and closes active session', () async {
      // Open
      await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/session/open'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'sessionId': 'sess-1', 'classId': 'cls-1'}),
        ),
      );

      // Close
      final closeRes = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/session/close'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'sessionId': 'sess-1',
            'classId': 'cls-1',
            'windowId': 'win-123',
          }),
        ),
      );

      expect(closeRes.statusCode, 200);
      final body = jsonDecode(await closeRes.readAsString());
      expect(body['success'], isTrue);
      expect(body['data']['status'], 'closed');
    });
  });
}
