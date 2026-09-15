import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Tầng Repository kết nối trực tiếp với Google Apps Script Data Gateway qua HTTPS
/// Tuân thủ quy ước kiến trúc 3 lớp (SRS v4.0 & docs/architecture.md)
class SheetsRepository {
  static const _gatewayTimeout = Duration(seconds: 60);

  final String gatewayUrl;
  final http.Client _client;

  SheetsRepository({String? gatewayUrl, http.Client? client})
      : gatewayUrl = gatewayUrl ??
            Platform.environment['APPS_SCRIPT_GATEWAY_URL'] ??
            'https://script.google.com/macros/s/AKfycbxcLHop2Gkp5zHtfdxRotjnIT45NIXnBIIZnlelWJ3aCaIy03zzQM3miOi6tAHZo6g/exec',
        _client = client ?? http.Client();

  /// Gửi POST Request đến Google Apps Script Gateway và xử lý 302 Redirect
  Future<Map<String, dynamic>> _postToGateway(
      String action, Map<String, dynamic> payload) async {
    if (gatewayUrl.isEmpty) {
      return {
        'success': false,
        'error': 'Chưa cấu hình APPS_SCRIPT_GATEWAY_URL'
      };
    }

    // Apps Script writes first, then redirects to googleusercontent.com for
    // the JSON response. That echo URL can occasionally return a transient
    // Drive 404 under a burst of sequential class saves. All M1 writes are
    // idempotent (upsert by classId), so retrying the complete request is safe.
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = http.Request('POST', Uri.parse(gatewayUrl))
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({
            'action': action,
            'payload': payload,
          });
        var response = await http.Response.fromStream(
          await _client.send(request).timeout(_gatewayTimeout),
        );

        if (response.statusCode == 302 ||
            response.statusCode == 301 ||
            response.statusCode == 303 ||
            response.statusCode == 307) {
          final redirectUrl = response.headers['location'];
          if (redirectUrl == null || redirectUrl.isEmpty) {
            throw StateError('Data Gateway không trả URL chuyển hướng.');
          }
          response = await _client
              .get(Uri.parse(redirectUrl))
              .timeout(_gatewayTimeout);
        }

        if (response.statusCode == 200) {
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          return {'success': true, 'data': decoded};
        }

        if (_isTransientGoogleEcho404(response) && attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        throw StateError(
          'Data Gateway trả về HTTP ${response.statusCode}. '
          'Vui lòng thử lại; dữ liệu đã lưu trước đó vẫn được giữ.',
        );
      } on StateError {
        rethrow;
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
          continue;
        }
      }
    }
    throw StateError('Không thể đọc phản hồi Data Gateway: $lastError');
  }

  bool _isTransientGoogleEcho404(http.Response response) {
    if (response.statusCode != 404) return false;
    final body = response.body.toLowerCase();
    return body.contains('google drive') ||
        body.contains('không tìm thấy trang') ||
        body.contains('not found');
  }

  /// Đồng bộ toàn bộ danh sách lớp học và tạo tab riêng cho từng lớp (kèm Tab Overview)
  Future<Map<String, dynamic>> syncAllClasses({
    required List<dynamic> classes,
    required String startDate,
  }) async {
    final res = await _postToGateway('syncAllClasses', {
      'classes': classes,
      'startDate': startDate,
    });
    return {
      'success': res['success'] == true,
      'spreadsheetUrl': res['data']?['spreadsheetUrl'],
      'classCount': res['data']?['classCount'] ?? classes.length,
      'message': 'Đã đồng bộ toàn bộ các lớp học lên Google Sheet thành công.',
    };
  }

  /// Khởi tạo bảng mẫu mặc định
  Future<bool> setupDatabase() async {
    final res = await _postToGateway('setupDatabase', {});
    return res['success'] == true;
  }

  /// Lưu thông tin Lớp học, Danh sách SV và các buổi học vào Google Sheets
  Future<bool> saveClassOffering({
    required Map<String, dynamic> offering,
    required List<Map<String, dynamic>> roster,
    required List<Map<String, dynamic>> lessons,
  }) async {
    final requestPayload = {
      'offering': offering,
      'roster': roster,
      'lessons': lessons,
    };
    Map<String, dynamic> res;
    try {
      res = await _postToGateway('saveClassOffering', requestPayload);
    } on StateError catch (error) {
      // A GAS Web App performs the spreadsheet write before it redirects to
      // googleusercontent.com. If that short-lived redirect responds 404,
      // verify the upsert through a fresh request instead of reporting a
      // false failure to the desktop app.
      if (!error.toString().contains('HTTP 404')) rethrow;
      final classId = offering['classId']?.toString() ?? '';
      if (classId.isEmpty) rethrow;
      try {
        final persisted = await _postToGateway('getSchedule', {
          'classId': classId,
        });
        if (persisted['success'] == true && persisted['data'] is Map) {
          return true;
        }
      } catch (_) {
        // Keep the original save error; it is more useful to the caller.
      }
      rethrow;
    }
    if (res['success'] != true) {
      final detail = res['error'] ?? res['data'] ?? jsonEncode(res);
      throw StateError(
        'Data Gateway từ chối lưu lịch: $detail',
      );
    }
    return res['success'] == true;
  }

  /// Batch version of [saveClassOffering]. The gateway reads and writes each
  /// canonical Sheet tab once for the full Markbook, rather than once/class.
  Future<bool> saveClassOfferings(
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final res = await _postToGateway('saveClassOfferings', {'items': items});
      if (res['success'] == true) return true;
      final detail = res['error'] ?? res['data'] ?? jsonEncode(res);
      if (!detail.toString().contains('Unknown action')) {
        throw StateError('Data Gateway từ chối lưu lịch: $detail');
      }
    } on StateError catch (error) {
      if (!error.toString().contains('Unknown action')) rethrow;
    }
    // Compatibility for an older deployed gateway. It remains functional but
    // is slower until the standalone Code.gs is redeployed with batch actions.
    for (final item in items) {
      await saveClassOffering(
        offering: Map<String, dynamic>.from(item['offering'] as Map),
        roster: (item['roster'] as List)
            .whereType<Map>()
            .map(
              (row) => Map<String, dynamic>.from(row),
            )
            .toList(),
        lessons: (item['lessons'] as List)
            .whereType<Map>()
            .map(
              (row) => Map<String, dynamic>.from(row),
            )
            .toList(),
      );
    }
    return true;
  }

  Future<bool> syncActiveClassIds(Set<String> activeClassIds) async {
    final res = await _postToGateway('syncActiveClassIds', {
      'activeClassIds': activeClassIds.toList(growable: false),
    });
    if (res['success'] != true) {
      final detail = res['error'] ?? res['data'] ?? jsonEncode(res);
      throw StateError('Data Gateway từ chối đồng bộ trạng thái lớp: $detail');
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> listSchedules() async {
    final res = await _postToGateway('listSchedules', {});
    if (res['success'] != true) {
      throw StateError(
        res['error']?.toString() ?? 'Data Gateway không trả danh sách lịch.',
      );
    }
    final data = res['data'];
    if (data is! List) return const [];
    return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Future<Map<String, dynamic>?> getSchedule(String classId) async {
    final res = await _postToGateway('getSchedule', {'classId': classId});
    if (res['success'] != true) {
      throw StateError(
        res['error']?.toString() ?? 'Data Gateway không trả lịch lớp.',
      );
    }
    final data = res['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<List<Map<String, dynamic>>> getAllSchedules() async {
    try {
      final res = await _postToGateway('getAllSchedules', {});
      if (res['success'] == true) {
        final data = res['data'];
        if (data is List) {
          return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
        }
      }
    } catch (_) {
      // The aggregate read is an optimization. A transient gateway failure,
      // an old deployment, or a malformed aggregate response must not prevent
      // restoring the same classes one at a time.
    }
    final summaries = await listSchedules();
    final schedules = <Map<String, dynamic>>[];
    for (final summary in summaries) {
      final classId = summary['classId']?.toString() ?? '';
      final schedule = classId.isEmpty ? null : await getSchedule(classId);
      if (schedule != null) schedules.add(schedule);
    }
    return schedules;
  }

  /// Mở ca điểm danh (FR-09, FR-10)
  Future<Map<String, dynamic>?> openAttendanceWindow(String sessionId) async {
    final res = await _postToGateway('openAttendanceWindow', {
      'sessionId': sessionId,
    });
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    return null;
  }

  /// Đóng ca điểm danh (FR-12)
  Future<bool> closeAttendanceWindow(String windowId) async {
    final res = await _postToGateway('closeAttendanceWindow', {
      'windowId': windowId,
    });
    return res['success'] == true;
  }

  /// Ghi nhận sinh viên check-in (FR-17, FR-19, FR-20, AC-10)
  Future<Map<String, dynamic>> recordCheckIn(
      String sessionId, String studentEmail) async {
    final res = await _postToGateway('saveCheckIn', {
      'sessionId': sessionId,
      'studentEmail': studentEmail,
    });
    return res;
  }

  /// Giảng viên sửa thủ công A <-> P (FR-14)
  Future<bool> recordManualOverride(
      String sessionId, String studentEmail, String status) async {
    final res = await _postToGateway('saveManualOverride', {
      'sessionId': sessionId,
      'studentEmail': studentEmail,
      'status': status,
    });
    return res['success'] == true;
  }

  /// Lấy danh sách kết quả điểm danh phục vụ Polling 5s (FR-11)
  Future<List<Map<String, dynamic>>> getAttendanceResults(
      String sessionId) async {
    final res = await _postToGateway('getAttendanceResults', {
      'sessionId': sessionId,
    });
    final dynamic data = res['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Lấy thông tin ca điểm danh đang mở
  Future<Map<String, dynamic>?> getActiveWindow(String sessionId) async {
    final res = await _postToGateway('getActiveWindow', {
      'sessionId': sessionId,
    });
    if (res['success'] == true && res['data'] is Map<String, dynamic>) {
      return res['data'] as Map<String, dynamic>;
    }
    return null;
  }

  /// Nạp dữ liệu mẫu 5 sinh viên để test (M5)
  Future<bool> seedSampleData(List<Map<String, dynamic>> students) async {
    final res = await _postToGateway('seedSampleData', {
      'students': students,
    });
    return res['success'] == true;
  }
}
