import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/attendance/models/attendance_state.dart';
import 'package:prm393_desktop/features/attendance/services/attendance_storage_service.dart';

void main() {
  test('AttendanceStorageService persists and restores attendance matrix across restarts', () async {
    const testFile = 'test_attendance_database.json';
    final storage = AttendanceStorageService(testFile);

    final mockStore = <String, Map<int, Map<String, LiveStudentAttendance>>>{
      '14_PRM393_SE1920': {
        1: {
          'cuong@gmail.com': const LiveStudentAttendance(
            studentEmail: 'cuong@gmail.com',
            studentName: 'Bảo Cường',
            rollNumber: 'SE193416',
            status: AttendanceStatus.present,
          ),
          'nhan@fpt.edu.vn': const LiveStudentAttendance(
            studentEmail: 'nhan@fpt.edu.vn',
            studentName: 'Hoàng Nhân',
            rollNumber: 'SE184226',
            status: AttendanceStatus.absent,
            isManualOverride: true,
          ),
        },
        2: {
          'cuong@gmail.com': const LiveStudentAttendance(
            studentEmail: 'cuong@gmail.com',
            studentName: 'Bảo Cường',
            rollNumber: 'SE193416',
            status: AttendanceStatus.present,
          ),
        },
      },
    };

    // 1. Save store to disk
    await storage.saveStore(mockStore);
    expect(File(testFile).existsSync(), isTrue);

    // 2. Simulate app restart by creating a fresh storage service instance
    final freshStorage = AttendanceStorageService(testFile);
    final loadedStore = await freshStorage.loadStore();

    // 3. Verify restored data
    expect(loadedStore.containsKey('14_PRM393_SE1920'), isTrue);
    final slot1 = loadedStore['14_PRM393_SE1920']?[1];
    expect(slot1, isNotNull);
    expect(slot1?['cuong@gmail.com']?.status, equals(AttendanceStatus.present));
    expect(slot1?['nhan@fpt.edu.vn']?.status, equals(AttendanceStatus.absent));
    expect(slot1?['nhan@fpt.edu.vn']?.isManualOverride, isTrue);

    final slot2 = loadedStore['14_PRM393_SE1920']?[2];
    expect(slot2?['cuong@gmail.com']?.status, equals(AttendanceStatus.present));

    // Clean up
    await storage.clearStore();
    expect(File(testFile).existsSync(), isFalse);
  });
}
