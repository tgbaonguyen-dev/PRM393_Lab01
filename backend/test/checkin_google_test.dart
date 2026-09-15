import 'dart:convert';

import 'package:backend/controllers/attendance_controller.dart';
import 'package:backend/repositories/sheets_repository.dart';
import 'package:backend/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';

const _clientId = 'test-client.apps.googleusercontent.com';
const _qrSecret = 'test-qr-secret';
const _sessionId = 'PRM393_SE1917_Lesson_1';
const _classId = 'SE1917';
const _studentEmail = 'student@fpt.edu.vn';

void main() {
  test('verified Google student is recorded as P', () async {
    final controller = _controller(
      gateway: _FakeGatewayClient(
        activeWindow: true,
        inClass: true,
        checkInResponse: {
          'success': true,
          'data': {'status': 'P', 'email': _studentEmail},
        },
      ),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/checkin'),
        body: jsonEncode({
          'idToken': 'google-id-token',
          'qrToken': _createQrToken(),
          'sessionId': _sessionId,
          'classId': _classId,
        }),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;

    expect(response.statusCode, 200);
    expect(body['success'], isTrue);
    expect(body['status'], 'SUCCESS');
    expect(body['data']['email'], _studentEmail);
    expect(body['data']['status'], 'P');
  });

  test('student outside the class roster is rejected', () async {
    final controller = _controller(
      gateway: _FakeGatewayClient(
        activeWindow: true,
        inClass: false,
        checkInResponse: {
          'success': false,
          'error': 'Không tìm thấy sinh viên trong lớp SE1917',
        },
      ),
    );

    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/checkin'),
        body: jsonEncode({
          'idToken': 'google-id-token',
          'qrToken': _createQrToken(),
          'sessionId': _sessionId,
          'classId': _classId,
        }),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;

    expect(response.statusCode, 403);
    expect(body['success'], isFalse);
    expect(body['status'], 'NOT_IN_ROSTER');
  });

  test('already recorded is returned without reporting a new success',
      () async {
    final controller = _controller(
      gateway: _FakeGatewayClient(
        activeWindow: true,
        inClass: true,
        checkInResponse: {
          'success': false,
          'status': 'ALREADY_CHECKED_IN',
          'data': {'status': 'P'},
        },
      ),
    );
    final body = await _postCheckin(controller);

    expect(body['success'], isFalse);
    expect(body['status'], 'ALREADY_CHECKED_IN');
  });

  test('closed session is rejected before saving attendance', () async {
    final controller = _controller(
      gateway: _FakeGatewayClient(
        activeWindow: false,
        inClass: true,
        checkInResponse: {'success': true},
      ),
    );
    final response = await _postCheckinResponse(controller);
    final body =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;

    expect(response.statusCode, 409);
    expect(body['status'], 'SESSION_CLOSED');
  });

  test('persistence failure is never reported as success', () async {
    final controller = _controller(
      gateway: _FakeGatewayClient(
        activeWindow: true,
        inClass: true,
        checkInResponse: {
          'success': false,
          'error': 'Google Sheets is unavailable',
        },
      ),
    );
    final body = await _postCheckin(controller);

    expect(body['success'], isFalse);
    expect(body['status'], 'PERSISTENCE_ERROR');
  });
}

Future<Response> _postCheckinResponse(AttendanceController controller) {
  return controller.router.call(
    Request(
      'POST',
      Uri.parse('http://localhost/checkin'),
      body: jsonEncode({
        'idToken': 'google-id-token',
        'qrToken': _createQrToken(),
        'sessionId': _sessionId,
        'classId': _classId,
      }),
    ),
  );
}

Future<Map<String, dynamic>> _postCheckin(
    AttendanceController controller) async {
  final response = await _postCheckinResponse(controller);
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

AttendanceController _controller({required http.Client gateway}) {
  return AttendanceController(
    authService: AuthService(
      client: _GoogleTokenClient(),
      expectedClientId: _clientId,
    ),
    sheetsRepository: SheetsRepository(
      gatewayUrl: 'https://gateway.test/exec',
      client: gateway,
    ),
    qrSecret: _qrSecret,
  );
}

String _createQrToken() {
  final payload = utf8.encode(jsonEncode({
    'classId': _classId,
    'sessionId': _sessionId,
    'expiresAt':
        DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
  }));
  final encodedPayload = base64Url.encode(payload).replaceAll('=', '');
  final signature = Hmac(sha256, utf8.encode(_qrSecret)).convert(payload);
  final encodedSignature =
      base64Url.encode(signature.bytes).replaceAll('=', '');
  return '$encodedPayload.$encodedSignature';
}

class _GoogleTokenClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'email': _studentEmail,
      'email_verified': 'true',
      'aud': _clientId,
      'exp': (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 300,
      'sub': 'google-subject-1',
      'name': 'Student Test',
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

class _FakeGatewayClient extends http.BaseClient {
  final bool activeWindow;
  final bool inClass;
  final Map<String, dynamic> checkInResponse;

  _FakeGatewayClient(
      {required this.activeWindow,
      required this.inClass,
      required this.checkInResponse});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final requestBody = jsonDecode(await request.finalize().bytesToString())
        as Map<String, dynamic>;
    final action = requestBody['action'];
    final response = switch (action) {
      'isStudentInClass' => {'success': true, 'data': inClass},
      'getActiveWindow' => {
          'success': true,
          'data': {'isOpen': activeWindow}
        },
      _ => checkInResponse,
    };
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(response))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}
