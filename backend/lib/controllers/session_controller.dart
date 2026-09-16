import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/qr_service.dart';
import '../services/session_service.dart';

class SessionController {
  final SessionService _sessionService;
  final QrService _qrService;
  final String _checkInBaseUrl;

  SessionController({
    SessionService? sessionService,
    QrService? qrService,
    String? checkInBaseUrl,
  })  : _sessionService = sessionService ?? SessionService(),
        _qrService = qrService ?? QrService(),
        _checkInBaseUrl = (checkInBaseUrl ??
                Platform.environment['STUDENT_CHECKIN_BASE_URL'] ??
                'http://localhost:3000/checkin')
            .trim();

  Router get router {
    final router = Router();
    router.post('/session/open', _open);
    router.post('/session/close', _close);
    router.get('/session/qr', _qr);
    return router;
  }

  Future<Response> _open(Request request) async {
    try {
      final body = await _readJson(request);
      final sessionId = _requiredString(body['sessionId']);
      final classId = _requiredString(body['classId']);
      final window = await _sessionService.openSession(
        sessionId: sessionId,
        classId: classId,
      );
      return _json(200, {
        'success': true,
        'message': 'Đã mở phiên điểm danh.',
        'data': window.toJson(),
      });
    } on FormatException catch (error) {
      return _error(400, 'BAD_REQUEST', error.message);
    } on SessionValidationException catch (error) {
      return _error(400, 'BAD_REQUEST', error.message);
    } on SessionPersistenceException catch (error) {
      return _error(502, 'PERSISTENCE_ERROR', error.message);
    } catch (_) {
      return _error(500, 'SERVER_ERROR', 'Không thể mở phiên điểm danh.');
    }
  }

  Future<Response> _close(Request request) async {
    try {
      final body = await _readJson(request);
      final sessionId = _requiredString(body['sessionId']);
      final classId = _requiredString(body['classId']);
      final windowId = _requiredString(body['windowId']);
      final window = await _sessionService.closeSession(
        sessionId: sessionId,
        classId: classId,
        windowId: windowId,
      );
      return _json(200, {
        'success': true,
        'message': 'Đã đóng phiên điểm danh.',
        'data': window.toJson(),
      });
    } on FormatException catch (error) {
      return _error(400, 'BAD_REQUEST', error.message);
    } on SessionValidationException catch (error) {
      return _error(400, 'BAD_REQUEST', error.message);
    } on SessionStateException catch (error) {
      return _error(409, error.code, error.message);
    } on SessionPersistenceException catch (error) {
      return _error(502, 'PERSISTENCE_ERROR', error.message);
    } catch (_) {
      return _error(500, 'SERVER_ERROR', 'Không thể đóng phiên điểm danh.');
    }
  }

  Future<Response> _qr(Request request) async {
    try {
      final sessionId = _requiredString(
        request.url.queryParameters['sessionId'],
      );
      final classId = _requiredString(request.url.queryParameters['classId']);
      final window = await _sessionService.requireOpenSession(
        sessionId: sessionId,
        classId: classId,
      );
      final token = _qrService.createToken(
        sessionId: window.sessionId,
        classId: window.classId,
        windowId: window.windowId,
      );
      final qrUrl = _buildCheckInUrl(
        token: token.value,
        sessionId: window.sessionId,
        classId: window.classId,
      );
      return _json(200, {
        'success': true,
        'data': {
          'qrToken': token.value,
          'expiresAt': token.expiresAt.millisecondsSinceEpoch,
          'qrUrl': qrUrl,
          'windowId': window.windowId,
          'sessionId': window.sessionId,
          'classId': window.classId,
        },
      });
    } on SessionValidationException catch (error) {
      return _error(400, 'BAD_REQUEST', error.message);
    } on SessionStateException catch (error) {
      return _error(409, error.code, error.message);
    } on SessionPersistenceException catch (error) {
      return _error(502, 'PERSISTENCE_ERROR', error.message);
    } on StateError catch (error) {
      return _error(500, 'CONFIG_ERROR', error.message);
    } on FormatException {
      return _error(
        500,
        'CONFIG_ERROR',
        'STUDENT_CHECKIN_BASE_URL không hợp lệ.',
      );
    } catch (_) {
      return _error(500, 'SERVER_ERROR', 'Không thể tạo mã QR.');
    }
  }

  String _buildCheckInUrl({
    required String token,
    required String sessionId,
    required String classId,
  }) {
    final base = Uri.parse(_checkInBaseUrl);
    if (!base.hasScheme || base.host.isEmpty) {
      throw const FormatException('STUDENT_CHECKIN_BASE_URL không hợp lệ.');
    }
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'token': token,
        'sessionId': sessionId,
        'classId': classId,
      },
    ).toString();
  }

  static Future<Map<String, dynamic>> _readJson(Request request) async {
    final source = await request.readAsString();
    if (source.trim().isEmpty) {
      throw const FormatException('Request body không được để trống.');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON request không hợp lệ.');
    }
    return decoded;
  }

  static String _requiredString(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      throw const SessionValidationException(
        'sessionId, classId và windowId bắt buộc khi endpoint yêu cầu.',
      );
    }
    return value.trim();
  }

  static Response _error(int statusCode, String code, String message) =>
      _json(statusCode, {'success': false, 'status': code, 'message': message});

  static Response _json(int statusCode, Map<String, dynamic> body) => Response(
        statusCode,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
}
