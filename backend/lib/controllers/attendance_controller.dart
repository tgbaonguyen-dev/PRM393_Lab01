import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/attendance_service.dart';

// Controller tiếp nhận Request liên quan đến Điểm danh & Sửa kết quả

class AttendanceController {
  final AttendanceService _attendanceService;

  AttendanceController({AttendanceService? attendanceService})
      : _attendanceService = attendanceService ?? AttendanceService();

  Router get router {
    final router = Router();

    //1 endpoint: phục vụ Polling 5s từ Desktop
    router.get('/session/<sessionId>/attendances', _handleGetAttendances);

    //2 endpoint: phục vụ sửa A/P thủ công từ Desktop
    router.post(
        '/session/<sessionId>/attendances/manual-override', _handleManualEdit);

    return router;
  }

  //Xử lý GET /session/<sessionId>/attendances
  Future<Response> _handleGetAttendances(
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
  Future<Response> _handleManualEdit(Request request) async {
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
}
