import 'dart:convert';

import 'package:backend/controllers/attendance_controller.dart';
import 'package:backend/repositories/sheets_repository.dart';
import 'package:backend/services/auth_service.dart';
import 'package:backend/services/qr_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('AttendanceController Routes', () {
    late AttendanceController controller;

    setUp(() {
      controller = AttendanceController(
        sheetsRepository: SheetsRepository(gatewayUrl: 'http://localhost'),
        authService: AuthService(),
        qrService: QrService(secret: 'test-secret-key-32-characters-long'),
      );
    });

    test('POST /checkin rejects empty payload with 400', () async {
      final res = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/checkin'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({}),
        ),
      );
      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isFalse);
      expect(body['status'], 'BAD_REQUEST');
    });

    test('POST /attendance/checkin rejects empty payload with 400', () async {
      final res = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/attendance/checkin'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({}),
        ),
      );
      expect(res.statusCode, 400);
      final body = jsonDecode(await res.readAsString());
      expect(body['success'], isFalse);
    });
  });
}
