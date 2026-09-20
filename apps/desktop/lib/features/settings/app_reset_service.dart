import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../config.dart';
import '../attendance/services/attendance_storage_service.dart';

class AppResetService {
  final http.Client client;
  final String baseUrl;
  AppResetService({http.Client? client, this.baseUrl = AppConfig.apiBaseUrl})
    : client = client ?? http.Client();

  Future<void> resetRemote(String key) async {
    final response = await client
        .post(
          Uri.parse('$baseUrl/app/reset'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $key',
          },
          body: jsonEncode({'confirmation': 'DELETE_ALL_APP_DATA'}),
        )
        .timeout(const Duration(minutes: 4));
    final dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw StateError(
        'Backend chưa hỗ trợ xóa dữ liệu hoặc không phản hồi hợp lệ.',
      );
    }
    if (response.statusCode != 200 || body is! Map || body['success'] != true) {
      throw StateError(
        body is Map
            ? body['error']?.toString() ?? 'Xóa chưa hoàn tất.'
            : 'Xóa chưa hoàn tất.',
      );
    }
  }

  /// Only application-owned JSON files; never source workbooks or exports.
  static List<File> localDataFiles(Directory start) {
    var root = start.absolute;
    var candidate = start.absolute;
    // Locate the repository boundary without touching files in unrelated ancestors.
    for (var i = 0; i < 5; i++) {
      if (File('${candidate.path}/apps/desktop/pubspec.yaml').existsSync()) {
        root = candidate;
        break;
      }
      if (candidate.parent.path == candidate.path) break;
      candidate = candidate.parent;
    }
    final paths = <String>{};
    for (final relative in [
      'attendance_database.json',
      'schedules_local.json',
      'apps/desktop/attendance_database.json',
      'backend/data/schedules_local.json',
    ]) {
      final file = File('${root.path}/$relative').absolute;
      if (file.existsSync()) paths.add(file.path);
    }
    return paths.map(File.new).toList();
  }

  Future<void> resetLocal({Directory? directory}) async {
    AttendanceStorageService.invalidatePendingWrites();
    for (final file in localDataFiles(directory ?? Directory.current)) {
      final schedule = file.path.endsWith('schedules_local.json');
      await file.writeAsString(
        schedule ? '{"classes":{},"activeClassIds":[]}' : '{}',
        flush: true,
      );
    }
  }

  void dispose() => client.close();
}
