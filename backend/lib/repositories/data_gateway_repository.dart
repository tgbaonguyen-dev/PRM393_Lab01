import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class DataGatewayRepository {
  final String gatewayUrl;

  DataGatewayRepository({String? gatewayUrl})
      : gatewayUrl = gatewayUrl ?? AppConfig.appsScriptGatewayUrl;

  Future<Map<String, dynamic>> _postToGateway(String action, Map<String, dynamic> payload) async {
    if (gatewayUrl.isEmpty) {
      return {'success': true, 'data': null};
    }

    var response = await http.post(
      Uri.parse(gatewayUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'payload': payload,
      }),
    );

    // Google Apps Script Web Apps respond with 302 Redirect to usercontent
    if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303 || response.statusCode == 307) {
      final redirectUrl = response.headers['location'];
      if (redirectUrl != null && redirectUrl.isNotEmpty) {
        response = await http.get(Uri.parse(redirectUrl));
      }
    }

    if (response.statusCode != 200) {
      throw Exception('Data Gateway returned HTTP ${response.statusCode}: ${response.body}');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'success': true, 'data': decoded};
  }

  Future<Map<String, dynamic>> syncAllClasses(List<dynamic> classes, String startDate) async {
    final res = await _postToGateway('syncAllClasses', {
      'classes': classes,
      'startDate': startDate,
    });
    final success = res['success'] == true && res['data'] != false && res['data'] != null;
    print('[DataGateway] syncAllClasses: success=$success');
    return {
      'success': success,
      'spreadsheetUrl': res['data']?['spreadsheetUrl'],
      'message': 'Đã đồng bộ toàn bộ các lớp học lên Google Sheet thành công.',
    };
  }

  Future<bool> saveCheckIn(String lessonId, String studentEmail) async {
    final res = await _postToGateway('saveCheckIn', {
      'lessonId': lessonId,
      'studentEmail': studentEmail,
    });
    final ok = res['success'] == true && res['data'] != false && res['data'] != null;
    print('[DataGateway] saveCheckIn ($lessonId, $studentEmail) -> ${ok ? "SUCCESS" : "FAILED"} (res: $res)');
    return ok;
  }

  Future<bool> saveManualOverride(String lessonId, String studentEmail, String status) async {
    final res = await _postToGateway('saveManualOverride', {
      'lessonId': lessonId,
      'studentEmail': studentEmail,
      'status': status,
    });
    final ok = res['success'] == true && res['data'] != false && res['data'] != null;
    print('[DataGateway] saveManualOverride ($lessonId, $studentEmail, $status) -> ${ok ? "SUCCESS" : "FAILED"} (res: $res)');
    return ok;
  }

  Future<List<Map<String, dynamic>>> getAttendanceResults(String lessonId) async {
    final res = await _postToGateway('getAttendanceResults', {
      'lessonId': lessonId,
    });
    final dynamic data = res['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>?> openAttendanceWindow(String lessonId) async {
    final res = await _postToGateway('openAttendanceWindow', {
      'lessonId': lessonId,
    });
    return res['data'] as Map<String, dynamic>?;
  }

  Future<bool> closeAttendanceWindow(String windowId) async {
    final res = await _postToGateway('closeAttendanceWindow', {
      'windowId': windowId,
    });
    return res['success'] == true;
  }

  Future<Map<String, dynamic>?> getActiveWindow(String lessonId) async {
    final res = await _postToGateway('getActiveWindow', {
      'lessonId': lessonId,
    });
    return res['data'] as Map<String, dynamic>?;
  }
}
