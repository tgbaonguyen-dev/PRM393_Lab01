import '../repositories/sheets_repository.dart';

// Service xử lý nghiệp vụ Điểm danh & Sửa kết quả thủ công
class AttendanceService {
  final SheetsRepository _sheetsRepository;

  AttendanceService({SheetsRepository? sheetsRepository})
      : _sheetsRepository = sheetsRepository ?? SheetsRepository();

// Lấy danh sách điểm danh của ca học và tính toán thống kê sĩ số
  Future<Map<String, dynamic>> getAttendanceSummary(String sessionId) async {
    if (sessionId.isEmpty) {
      throw ArgumentError('Session ID cannot be empty');
    }

    //1 goi repository để lấy danh sách điểm danh
    final List<Map<String, dynamic>> records =
        await _sheetsRepository.getAttendanceResults(sessionId);

    //2 tinh toán thống kê sĩ số
    int presentCount = 0;
    int absentCount = 0;

    for (final row in records) {
      final status =
          (row['status'] ?? row['Status'] ?? '').toString().toUpperCase();
      if (status == 'P') {
        presentCount++;
      } else if (status == 'A') {
        absentCount++;
      }
    }

    return {
      'sessionId': sessionId,
      'summary': {
        'total': records.length,
        'present': presentCount,
        'absent': absentCount,
      },
      'students': records,
    };
  }

  // Giảng viên sửa A/P thủ công
  // Sửa của GV có ưu tiên cao nhất, đánh dấu isManualEdited = true
  Future<bool> manualOverride({
    required String sessionId,
    required String studentEmail,
    required String status,
  }) async {
    final newStatus = status.trim().toUpperCase();
    if (newStatus != 'P' && newStatus != 'A') {
      throw ArgumentError('Status must be either "P" or "A"');
    }
    if (sessionId.trim().isEmpty || studentEmail.trim().isEmpty) {
      throw ArgumentError('Session ID and Student Email cannot be empty');
    }

    return await _sheetsRepository.recordManualOverride(
        sessionId, studentEmail.trim(), newStatus);
  }
}
