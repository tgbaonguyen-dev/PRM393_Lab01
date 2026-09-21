import 'package:prm393_desktop/features/attendance/services/attendance_storage_service.dart';

class MemoryAttendance extends AttendanceStorageService {
  Map<String, Map<int, Map<String, String>>> data = {};
  int refreshCount = 0;
  @override
  Future<Map<String, Map<int, Map<String, String>>>> loadStore() async => data;
  @override
  Future<void> saveStore(Map<String, Map<int, Map<String, String>>> store) async { data = store; }
  @override
  Future<Map<String, Map<int, Map<String, String>>>> fetchLatestStore() async {
    refreshCount++;
    return data;
  }
}
