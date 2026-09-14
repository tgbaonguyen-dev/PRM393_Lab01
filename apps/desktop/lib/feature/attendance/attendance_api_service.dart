import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/attendance_model.dart';

// Service gọi API Backend phục vụ Polling và Sửa tay A/P (Thành viên 4)
class AttendanceApiService {
  final String baseUrl;
  final http.Client _client;
  AttendanceApiService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? 'http://127.0.0.1:8080',
      _client = client ?? http.Client();

  // 1. Gọi GET /session/<sessionId>/attendances để lấy dữ liệu polling 5s
  Future<({AttendanceSummary summary, List<StudentAttendanceRecord> students})>
  getAttendances(String sessionId) async {
    final uri = Uri.parse('$baseUrl/session/$sessionId/attendances');
    final response = await _client.get(uri);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['success'] == true && decoded['data'] != null) {
        final data = decoded['data'];
        final summary = AttendanceSummary.fromJson(data['summary'] ?? {});
        final rawList = (data['students'] as List<dynamic>?) ?? [];
        final students = rawList
            .map(
              (item) => StudentAttendanceRecord.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList();
        return (summary: summary, students: students);
      }
      throw Exception(decoded['error'] ?? 'Dữ liệu không hợp lệ');
    } else {
      throw Exception('Lỗi HTTP ${response.statusCode}: ${response.body}');
    }
  }

  // 2. Gọi POST /attendance/manual-edit khi Giảng viên bấm sửa tay A <-> P
  Future<bool> updateManualStatus({
    required String sessionId,
    required String studentEmail,
    required String newStatus,
  }) async {
    final uri = Uri.parse('$baseUrl/attendance/manual-edit');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'studentEmail': studentEmail,
        'status': newStatus,
      }),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['success'] == true;
    }
    return false;
  }
}
