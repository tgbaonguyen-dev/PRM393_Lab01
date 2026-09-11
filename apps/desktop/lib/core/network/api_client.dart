import 'dart:convert';
import 'package:http/http.dart' as http;

/// API Client communicating with Next.js Backend API
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Requests a newly generated rotating QR token for an active window
  Future<Map<String, dynamic>?> generateQrToken(String windowId, String lessonId) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/qr/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'windowId': windowId, 'lessonId': lessonId}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Polls current attendance results every 5 seconds
  Future<Map<String, dynamic>?> pollAttendance(String lessonId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/attendance/poll?lessonId=$lessonId'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Batch syncs all classes with selected startDate to Google Sheets
  Future<Map<String, dynamic>?> syncAllClasses({
    required List<Map<String, dynamic>> classes,
    required String startDate,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/class/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'classes': classes,
          'startDate': startDate,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Syncs Class Offering, Roster, and Lessons to Cloud (Next.js & Google Sheets)
  Future<bool> syncClassOffering({
    required Map<String, dynamic> offering,
    required List<Map<String, dynamic>> roster,
    required List<Map<String, dynamic>> lessons,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/class/sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'offering': offering,
          'roster': roster,
          'lessons': lessons,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Opens an attendance window on the server
  Future<Map<String, dynamic>?> openWindow(String lessonId) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/attendance/window'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'open',
          'lessonId': lessonId,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Closes the active window
  Future<bool> closeWindow(String windowId) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/attendance/window'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'close',
          'windowId': windowId,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
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
