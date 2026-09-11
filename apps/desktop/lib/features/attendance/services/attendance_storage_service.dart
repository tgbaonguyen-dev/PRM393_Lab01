import 'dart:convert';
import 'dart:io';
import '../models/attendance_state.dart';

/// Local JSON persistence service for attendance records across application restarts
class AttendanceStorageService {
  static const String defaultFileName = 'attendance_database.json';
  final File storageFile;

  AttendanceStorageService([String? filePath])
      : storageFile = File(filePath ?? defaultFileName);

  /// Saves the entire attendance matrix to a persistent local JSON file
  Future<void> saveStore(Map<String, Map<int, Map<String, LiveStudentAttendance>>> store) async {
    try {
      final jsonMap = <String, dynamic>{};
      store.forEach((sheetName, slots) {
        final slotsMap = <String, dynamic>{};
        slots.forEach((slotNum, students) {
          final studentsMap = <String, dynamic>{};
          students.forEach((email, attendance) {
            studentsMap[email] = attendance.toMap();
          });
          slotsMap['$slotNum'] = studentsMap;
        });
        jsonMap[sheetName] = slotsMap;
      });

      const encoder = JsonEncoder.withIndent('  ');
      await storageFile.writeAsString(encoder.convert(jsonMap));
    } catch (_) {
      // In desktop environments, fallback gracefully if writing fails
    }
  }

  /// Loads the persisted attendance matrix from local storage on startup
  Future<Map<String, Map<int, Map<String, LiveStudentAttendance>>>> loadStore() async {
    final store = <String, Map<int, Map<String, LiveStudentAttendance>>>{};
    if (!storageFile.existsSync()) return store;

    try {
      final content = await storageFile.readAsString();
      if (content.trim().isEmpty) return store;

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return store;

      decoded.forEach((sheetName, slotsDynamic) {
        if (slotsDynamic is Map<String, dynamic>) {
          final slotMap = <int, Map<String, LiveStudentAttendance>>{};
          slotsDynamic.forEach((slotKey, studentsDynamic) {
            final slotNum = int.tryParse(slotKey);
            if (slotNum != null && studentsDynamic is Map<String, dynamic>) {
              final studentMap = <String, LiveStudentAttendance>{};
              studentsDynamic.forEach((email, studentDynamic) {
                if (studentDynamic is Map<String, dynamic>) {
                  studentMap[email.toLowerCase()] = LiveStudentAttendance.fromMap(studentDynamic);
                }
              });
              slotMap[slotNum] = studentMap;
            }
          });
          store[sheetName] = slotMap;
        }
      });
    } catch (_) {
      // Fallback gracefully on parsing error
    }
    return store;
  }

  /// Clears stored records (e.g. for testing or reset)
  Future<void> clearStore() async {
    if (storageFile.existsSync()) {
      await storageFile.delete();
    }
  }
}
