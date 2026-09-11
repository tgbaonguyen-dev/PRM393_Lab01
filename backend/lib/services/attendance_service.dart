import '../repositories/data_gateway_repository.dart';
import 'qr_service.dart';

class CheckInResult {
  final bool success;
  final String message;
  final int statusCode;

  CheckInResult({
    required this.success,
    required this.message,
    required this.statusCode,
  });
}

class AttendanceService {
  final DataGatewayRepository repo;
  final QrService qr;

  AttendanceService({
    DataGatewayRepository? repo,
    QrService? qr,
  })  : repo = repo ?? DataGatewayRepository(),
        qr = qr ?? QrService();

  Future<Map<String, dynamic>?> openWindow(String lessonId) async {
    return repo.openAttendanceWindow(lessonId);
  }

  Future<bool> closeWindow(String windowId) async {
    return repo.closeAttendanceWindow(windowId);
  }

  Future<CheckInResult> processCheckIn({
    required String qrToken,
    required String studentEmail,
  }) async {
    // 1. Validate QR Token
    final qrValidation = qr.validateToken(qrToken);
    if (!qrValidation.isValid || qrValidation.lessonId == null) {
      return CheckInResult(
        success: false,
        message: qrValidation.error ?? 'Mã QR không hợp lệ hoặc đã hết hạn.',
        statusCode: 400,
      );
    }

    final lessonId = qrValidation.lessonId!;
    final windowId = qrValidation.windowId;

    // 2. Validate Window State
    final activeWindow = await repo.getActiveWindow(lessonId);
    if (activeWindow == null || activeWindow['isOpen'] != true || activeWindow['id'] != windowId) {
      return CheckInResult(
        success: false,
        message: 'Ca điểm danh đã kết thúc hoặc không còn mở.',
        statusCode: 403,
      );
    }

    final normalizedEmail = studentEmail.trim().toLowerCase();

    // 3. Check existing attendance result
    final currentResults = await repo.getAttendanceResults(lessonId);
    final existing = currentResults.where(
      (r) => (r['studentEmail'] as String? ?? '').toLowerCase() == normalizedEmail,
    ).firstOrNull;

    if (existing?['status'] == 'P') {
      return CheckInResult(
        success: true,
        message: 'Bạn đã điểm danh thành công trước đó.',
        statusCode: 200,
      );
    }

    // 4. Save Check-in directly to the class sheet
    final saved = await repo.saveCheckIn(lessonId, normalizedEmail);
    if (!saved) {
      return CheckInResult(
        success: false,
        message: 'Điểm danh không thành công. Email của bạn không nằm trong danh sách sinh viên của lớp học này.',
        statusCode: 403,
      );
    }

    return CheckInResult(
      success: true,
      message: 'Điểm danh thành công!',
      statusCode: 200,
    );
  }

  Future<bool> applyManualOverride({
    required String lessonId,
    required String studentEmail,
    required String status,
  }) async {
    final normalizedEmail = studentEmail.trim().toLowerCase();
    return repo.saveManualOverride(lessonId, normalizedEmail, status);
  }

  Future<List<Map<String, dynamic>>> getPollResults(String lessonId) async {
    return repo.getAttendanceResults(lessonId);
  }
}
