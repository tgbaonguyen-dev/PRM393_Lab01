import 'dart:convert';
import 'dart:io';

/// Dịch vụ lưu trữ và đọc kết quả điểm danh cục bộ giữa các phiên làm việc
class AttendanceStorageService {
  static const String defaultFileName = 'attendance_database.json';
  final String? customFilePath;

  AttendanceStorageService([this.customFilePath]);

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

  /// Xóa toàn bộ dữ liệu điểm danh (dùng khi import markbook mới)
  Future<void> resetStore() async {
    await saveStore(<String, Map<int, Map<String, String>>>{});
  }
}
