import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../repositories/sheets_repository.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/qr_service.dart';
import '../services/schedule_service.dart';

// Controller tiếp nhận Request liên quan đến Điểm danh & Sửa kết quả

class AttendanceController {
  final AttendanceService _attendanceService;
  final AuthService _authService;
  final SheetsRepository _sheetsRepository;
  final ScheduleRepository? _scheduleRepository;
  final QrService _qrService;

  AttendanceController({
    AttendanceService? attendanceService,
    AuthService? authService,
    SheetsRepository? sheetsRepository,
    ScheduleRepository? scheduleRepository,
    String? qrSecret,
    QrService? qrService,
  })  : _attendanceService = attendanceService ?? AttendanceService(),
        _authService = authService ?? AuthService(),
        _sheetsRepository = sheetsRepository ?? SheetsRepository(),
        _scheduleRepository = scheduleRepository,
        _qrService = qrService ?? QrService(secret: qrSecret);


  Router get router {
    final router = Router();

    //1 endpoint: phục vụ Polling 5s từ Desktop
    router.get('/session/<sessionId>/attendances', handleGetAttendances);
    router.get('/<sessionId>/attendances', handleGetAttendances);

    //2 endpoint: phục vụ sửa A/P thủ công từ Desktop
    router.post(
        '/session/<sessionId>/attendances/manual-override', handleManualEdit);
    router.post(
        '/<sessionId>/attendances/manual-override', handleManualEdit);
    router.post('/manual-edit', handleManualEdit);
    router.post('/attendance/manual-edit', handleManualEdit);
    router.post('/checkin', _handleCheckIn);
    router.post('/attendance/checkin', _handleCheckIn);

    return router;
  }

  //Xử lý GET /session/<sessionId>/attendances
  Future<Response> handleGetAttendances(
      Request request, String sessionId) async {
    try {
      if (sessionId.trim().isEmpty) {
        return Response.badRequest(
          body:
              jsonEncode({'success': false, 'error': 'sessionId không hợp lệ'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _attendanceService.getAttendanceSummary(sessionId);

      return Response.ok(
        jsonEncode({'success': true, 'data': result}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // Xử lý POST /attendance/manual-edit
  Future<Response> handleManualEdit(Request request) async {
    try {
      final bodyString = await request.readAsString();
      if (bodyString.isEmpty) {
        return Response.badRequest(
          body:
              jsonEncode({'success': false, 'error': 'Request body is empty'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final Map<String, dynamic> data = jsonDecode(bodyString);
      final String? sessionId = data['sessionId'];
      final String? studentEmail = data['studentEmail'];
      final String? status = data['status'];

      if (sessionId == null ||
          studentEmail == null ||
          status == null ||
          sessionId.trim().isEmpty ||
          studentEmail.trim().isEmpty ||
          status.trim().isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'success': false,
            'error':
                'sessionId, studentEmail, and status are required and cannot be empty'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final success = await _attendanceService.manualOverride(
        sessionId: sessionId,
        studentEmail: studentEmail,
        status: status,
      );

      if (success) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'message': 'Đã cập nhật kết quả điểm danh thủ công thành công',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.internalServerError(
          body: jsonEncode({
            'success': false,
            'error': 'Không thể lưu kết quả vào Data Gateway',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } on ArgumentError catch (e) {
      return Response.badRequest(
        body: jsonEncode({'success': false, 'error': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _handleCheckIn(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      if (body is! Map<String, dynamic>) {
        return _jsonError(400, 'BAD_REQUEST', 'Request body không hợp lệ.');
      }

      final idToken = _requiredString(body['idToken']);
      final qrToken = _requiredString(body['qrToken'] ?? body['token']);
      final sessionId = _requiredString(body['sessionId']);
      final classId = _requiredString(body['classId']);
      if ([idToken, qrToken, sessionId, classId]
          .any((value) => value.isEmpty)) {
        return _jsonError(400, 'BAD_REQUEST',
            'Cần có idToken, qrToken, sessionId và classId.');
      }

      final identity = await _authService.verifyGoogleIdToken(idToken);
      if (identity == null) {
        return _jsonError(401, 'AUTH_FAILED',
            'Google ID Token không hợp lệ hoặc đã hết hạn.');
      }

      final qr = _qrService.verifyToken(
        qrToken,
        expectedSessionId: sessionId,
        expectedClassId: classId,
      );
      if (qr == null) {
        return _jsonError(400, 'QR_EXPIRED',
            'Mã QR không hợp lệ hoặc đã hết hạn. Vui lòng quét mã mới nhất.');
      }

      print('[CheckIn] Yêu cầu điểm danh: email=${identity.email}, classId=$classId, sessionId=$sessionId');

      bool? isStudentAllowed;
      if (_scheduleRepository != null) {
        try {
          final schedule = await _scheduleRepository!.get(classId);
          if (schedule != null) {
            final studentsRaw = schedule['students'] ?? schedule['roster'];
            if (studentsRaw is List && studentsRaw.isNotEmpty) {
              final roster = studentsRaw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              isStudentAllowed = _authService.isStudentInRoster(
                email: identity.email,
                roster: roster,
              );
            }
          }
        } catch (_) {}
      }

      if (isStudentAllowed == null) {
        isStudentAllowed = await _sheetsRepository.isStudentInClass(
          classId: classId,
          email: identity.email,
        );
      }

      if (isStudentAllowed == false) {
        return _jsonError(403, 'NOT_IN_ROSTER',
            'Email Google (${identity.email}) không thuộc danh sách lớp học phần $classId.');
      }


      final activeWindow = await _sheetsRepository.getActiveWindow(sessionId);
      if (activeWindow == null || activeWindow['isOpen'] != true) {
        return _jsonError(409, 'SESSION_CLOSED',
            'Phiên điểm danh đã đóng hoặc chưa được mở.');
      }

      final activeWindowId =
          (activeWindow['windowId'] ?? activeWindow['id'])?.toString().trim();
      if (activeWindowId == null ||
          activeWindowId.isEmpty ||
          qr.windowId != activeWindowId) {
        return _jsonError(400, 'QR_EXPIRED',
            'Mã QR thuộc phiên cũ. Vui lòng quét mã mới nhất.');
      }

      final result = await _sheetsRepository.recordCheckIn(
        sessionId,
        identity.email,
      );
      final data = result['data'] is Map<String, dynamic>
          ? result['data'] as Map<String, dynamic>
          : <String, dynamic>{};
      final gatewayStatus =
          (result['status'] ?? data['status'])?.toString().toUpperCase();
      if (gatewayStatus == 'ALREADY_CHECKED_IN' ||
          result['alreadyRecorded'] == true) {
        return _jsonResponse(200, false, 'ALREADY_CHECKED_IN',
            'Bạn đã được điểm danh trước đó.', {
          'email': identity.email,
          'status': 'P',
        });
      }

      if (result['success'] != true || data['success'] == false) {
        final error = (result['error'] ?? data['error'])?.toString() ??
            'Không thể lưu kết quả điểm danh.';
        if (error.toLowerCase().contains('không tìm thấy sinh viên')) {
          return _jsonError(403, 'NOT_IN_ROSTER',
              'Email Google này không thuộc danh sách lớp học phần.');
        }
        return _jsonError(502, 'PERSISTENCE_ERROR', error);
      }

      return _jsonResponse(200, true, 'SUCCESS', 'Điểm danh thành công.', {
        'email': identity.email,
        'studentName': identity.name,
        'status': 'P',
      });
    } on FormatException {
      return _jsonError(400, 'BAD_REQUEST', 'JSON request không hợp lệ.');
    } catch (_) {
      return _jsonError(502, 'PERSISTENCE_ERROR',
          'Không thể lưu kết quả điểm danh. Vui lòng thử lại.');
    }
  }

  String _requiredString(dynamic value) => value is String ? value.trim() : '';

  Response _jsonError(int code, String status, String message) =>
      _jsonResponse(code, false, status, message, null);

  Response _jsonResponse(
    int code,
    bool success,
    String status,
    String message,
    Map<String, dynamic>? data,
  ) {
    return Response(
      code,
      body: jsonEncode({
        'success': success,
        'status': status,
        'message': message,
        if (data != null) 'data': data,
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
