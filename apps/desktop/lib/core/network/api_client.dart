import 'dart:convert';
import 'package:http/http.dart' as http;

/// API Client communicating with Next.js Backend API
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Requests a newly generated rotating QR token for an active window
  Future<Map<String, dynamic>> generateQrToken(String windowId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/qr/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'windowId': windowId}),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Polls current attendance results every 5 seconds
  Future<Map<String, dynamic>> pollAttendance(String windowId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/attendance/poll?windowId=$windowId'),
      headers: {'Content-Type': 'application/json'},
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Closes the active window
  Future<bool> closeWindow(String windowId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/attendance/window/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'windowId': windowId}),
    );
    return response.statusCode == 200;
  }

  /// Manually overrides a student attendance result
  Future<bool> manualOverride({
    required String lessonId,
    required String studentEmail,
    required String status, // 'P' or 'A'
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/attendance/override'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'lessonId': lessonId,
        'studentEmail': studentEmail,
        'status': status,
      }),
    );
    return response.statusCode == 200;
  }
}
