import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../config.dart';

/// Dịch vụ lưu trữ và đọc kết quả điểm danh cục bộ giữa các phiên làm việc
class AttendanceStorageService {
  static const String defaultFileName = 'attendance_database.json';
  final String? customFilePath;
  final http.Client _httpClient;

  AttendanceStorageService([this.customFilePath, http.Client? client])
    : _httpClient = client ?? http.Client();

  File get storageFile => _resolveFile(customFilePath);

  static File _resolveFile([String? filePath]) {
    if (filePath != null) return File(filePath);

    final candidates = [
      'attendance_database.json',
      'apps/desktop/attendance_database.json',
      '../attendance_database.json',
    ];

    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }

    if (Directory('apps/desktop').existsSync()) {
      return File('apps/desktop/attendance_database.json');
    }

    return File('attendance_database.json');
  }

  /// Lưu ma trận điểm danh (sheetName -> slotNum -> (email -> status P/A))
  Future<void> saveStore(
    Map<String, Map<int, Map<String, String>>> store,
  ) async {
    try {
      final jsonMap = <String, dynamic>{};
      store.forEach((sheetName, slots) {
        final slotsMap = <String, dynamic>{};
        slots.forEach((slotNum, students) {
          slotsMap['$slotNum'] = students;
        });
        jsonMap[sheetName] = slotsMap;
      });

      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(jsonMap);

      final targetFile = storageFile;
      await targetFile.create(recursive: true);
      await targetFile.writeAsString(jsonString);

      // Nếu đang chạy từ thư mục gốc, cập nhật luôn cả apps/desktop nếu có
      final desktopFile = File('apps/desktop/attendance_database.json');
      if (desktopFile.path != targetFile.path &&
          Directory('apps/desktop').existsSync()) {
        await desktopFile.writeAsString(jsonString);
      }
    } catch (_) {}
  }

  /// Tải ma trận điểm danh từ file JSON
  Future<Map<String, Map<int, Map<String, String>>>> loadStore() async {
    final store = <String, Map<int, Map<String, String>>>{};
    final file = storageFile;
    if (!file.existsSync()) return store;

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return store;

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return store;

      decoded.forEach((sheetName, slotsDynamic) {
        if (slotsDynamic is Map<String, dynamic>) {
          final slotMap = <int, Map<String, String>>{};
          slotsDynamic.forEach((slotKey, studentsDynamic) {
            final slotNum = int.tryParse(slotKey);
            if (slotNum != null && studentsDynamic is Map<String, dynamic>) {
              final studentMap = <String, String>{};
              studentsDynamic.forEach((email, status) {
                studentMap[email.toLowerCase()] = status.toString();
              });
              slotMap[slotNum] = studentMap;
            }
          });
          store[sheetName] = slotMap;
        }
      });
    } catch (_) {}
    return store;
  }

  /// Kéo toàn bộ ma trận điểm danh từ Google Sheets (qua Backend API) về và hợp nhất vào local storage
  Future<bool> pullFromRemote([String? baseUrl]) async {
    try {
      final url = baseUrl ?? AppConfig.apiBaseUrl;
      final uri = Uri.parse('$url/attendance/all');
      final res = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return false;

      final dynamic decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map || decoded['success'] != true) {
        return false;
      }

      final dynamic remoteData = decoded['data'];
      if (remoteData is! Map) return false;

      final currentStore = await loadStore();

      remoteData.forEach((classKey, slotsDynamic) {
        if (slotsDynamic is Map) {
          final classStore = currentStore.putIfAbsent(
            classKey.toString(),
            () => <int, Map<String, String>>{},
          );
          slotsDynamic.forEach((slotKey, studentsDynamic) {
            final slotNum = int.tryParse(slotKey.toString());
            if (slotNum != null && studentsDynamic is Map) {
              final studentMap = classStore.putIfAbsent(
                slotNum,
                () => <String, String>{},
              );
              studentsDynamic.forEach((email, status) {
                final normalizedEmail = email.toString().trim().toLowerCase();
                final normalizedStatus = status.toString().trim().toUpperCase();
                if (normalizedEmail.isNotEmpty &&
                    (normalizedStatus == 'P' || normalizedStatus == 'A')) {
                  studentMap[normalizedEmail] = normalizedStatus;
                }
              });
            }
          });
        }
      });

      await saveStore(currentStore);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Xóa toàn bộ dữ liệu điểm danh (dùng khi import markbook mới)
  Future<void> resetStore() async {
    await saveStore(<String, Map<int, Map<String, String>>>{});
  }

  /// Lấy ma trận điểm danh hợp nhất cho một lớp từ tất cả các alias key khả dĩ trong store
  static Map<int, Map<String, String>> resolveClassAttendance({
    required Map<String, Map<int, Map<String, String>>> store,
    String? scheduleCode,
    required String subjectCode,
    required String classCode,
    String? customClassName,
  }) {
    final candidateKeys = <String>[
      if (scheduleCode != null && scheduleCode.isNotEmpty)
        '${scheduleCode}_${subjectCode}_$classCode',
      '$subjectCode - $classCode',
      '${subjectCode}_$classCode',
      if (customClassName != null && customClassName.isNotEmpty) customClassName,
      classCode,
    ];

    final merged = <int, Map<String, String>>{};
    for (final key in candidateKeys) {
      final slotMap = store[key];
      if (slotMap != null) {
        for (final entry in slotMap.entries) {
          final slotNum = entry.key;
          final studentMap = merged.putIfAbsent(slotNum, () => <String, String>{});
          for (final sEntry in entry.value.entries) {
            final email = sEntry.key.trim().toLowerCase();
            final st = sEntry.value.trim().toUpperCase();
            if (st == 'P') {
              studentMap[email] = 'P';
            } else if (st == 'A') {
              studentMap.putIfAbsent(email, () => 'A');
            }
          }
        }
      }
    }
    return merged;
  }
}
