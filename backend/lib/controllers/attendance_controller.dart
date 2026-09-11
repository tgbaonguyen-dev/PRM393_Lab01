import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/attendance_service.dart';

class AttendanceController {
  final AttendanceService attendanceService;

  AttendanceController({AttendanceService? attendanceService})
      : attendanceService = attendanceService ?? AttendanceService();

  Router get router {
    final router = Router();

    // POST /api/attendance/checkin
    router.post('/checkin', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final qrToken = body['qrToken'] as String?;
        final clientEmail = body['clientEmail'] as String?;

        if (qrToken == null || qrToken.isEmpty) {
          return Response(400,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'error': 'Mã QR không được để trống'}));
        }

        final email = clientEmail ?? '';
        if (email.isEmpty) {
          return Response(401,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'error': 'Không tìm thấy thông tin email sinh viên.'}));
        }

        final result = await attendanceService.processCheckIn(
          qrToken: qrToken,
          studentEmail: email,
        );

        return Response(
          result.statusCode,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'success': result.success,
            'message': result.message,
          }),
        );
      } catch (e) {
        return Response(500,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Lỗi xử lý điểm danh: $e'}));
      }
    });

    // POST /api/attendance/override
    router.post('/override', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final lessonId = body['lessonId'] as String?;
        final studentEmail = body['studentEmail'] as String?;
        final status = body['status'] as String?;

        if (lessonId == null || studentEmail == null || status == null) {
          return Response(400,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'error': 'Thiếu tham số (lessonId, studentEmail, status)'}));
        }

        if (status != 'A' && status != 'P') {
          return Response(400,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'error': 'Status phải là A hoặc P'}));
        }

        final ok = await attendanceService.applyManualOverride(
          lessonId: lessonId,
          studentEmail: studentEmail,
          status: status,
        );

        return Response.ok(
          jsonEncode({'success': ok}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(500,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Lỗi điều chỉnh điểm danh: $e'}));
      }
    });

    // GET /api/attendance/poll?lessonId=...
    router.get('/poll', (Request request) async {
      try {
        final lessonId = request.url.queryParameters['lessonId'];
        if (lessonId == null || lessonId.isEmpty) {
          return Response(400,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'error': 'Thiếu tham số lessonId'}));
        }

        final results = await attendanceService.getPollResults(lessonId);
        return Response.ok(
          jsonEncode({
            'success': true,
            'lessonId': lessonId,
            'results': results,
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(500,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Lỗi lấy kết quả điểm danh: $e'}));
      }
    });

    // POST /api/attendance/window
    router.post('/window', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final action = body['action'] as String?;

        if (action == 'open') {
          final lessonId = body['lessonId'] as String?;
          if (lessonId == null || lessonId.isEmpty) {
            return Response(400,
                headers: {'content-type': 'application/json'},
                body: jsonEncode({'error': 'Thiếu lessonId để mở ca'}));
          }
          final window = await attendanceService.openWindow(lessonId);
          return Response.ok(
            jsonEncode({'success': true, 'window': window}),
            headers: {'content-type': 'application/json'},
          );
        } else if (action == 'close') {
          final windowId = body['windowId'] as String?;
          if (windowId == null || windowId.isEmpty) {
            return Response(400,
                headers: {'content-type': 'application/json'},
                body: jsonEncode({'error': 'Thiếu windowId để đóng ca'}));
          }
          final ok = await attendanceService.closeWindow(windowId);
          return Response.ok(
            jsonEncode({'success': ok, 'message': 'Đã đóng ca điểm danh'}),
            headers: {'content-type': 'application/json'},
          );
        }

        return Response(400,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Action không hợp lệ (chỉ hỗ trợ open hoặc close)'}));
      } catch (e) {
        return Response(500,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Lỗi quản lý ca điểm danh: $e'}));
      }
    });

    return router;
  }
}
