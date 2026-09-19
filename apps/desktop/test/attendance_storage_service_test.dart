import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/attendance/services/attendance_storage_service.dart';

void main() {
  group('AttendanceStorageService.resolveClassAttendance', () {
    test('merges attendance from sheet key and desktop class name key', () {
      final store = <String, Map<int, Map<String, String>>>{
        '13_PRN232_SE1920': {
          1: {
            'student1@fpt.edu.vn': 'A',
            'student2@fpt.edu.vn': 'A',
          },
        },
        'PRN232 - SE1920': {
          1: {
            'student1@fpt.edu.vn': 'P',
          },
          3: {
            'student1@fpt.edu.vn': 'P',
            'student2@fpt.edu.vn': 'A',
          },
        },
      };

      final resolved = AttendanceStorageService.resolveClassAttendance(
        store: store,
        scheduleCode: '13',
        subjectCode: 'PRN232',
        classCode: 'SE1920',
      );

      // Slot 1: 'PRN232 - SE1920' has updated student1 to 'P'
      expect(resolved.containsKey(1), isTrue);
      expect(resolved[1]!['student1@fpt.edu.vn'], 'P');
      expect(resolved[1]!['student2@fpt.edu.vn'], 'A');

      // Slot 3: resolved from 'PRN232 - SE1920'
      expect(resolved.containsKey(3), isTrue);
      expect(resolved[3]!['student1@fpt.edu.vn'], 'P');
      expect(resolved[3]!['student2@fpt.edu.vn'], 'A');
    });

    test('returns empty map when no matching class exists', () {
      final store = <String, Map<int, Map<String, String>>>{};
      final resolved = AttendanceStorageService.resolveClassAttendance(
        store: store,
        scheduleCode: '13',
        subjectCode: 'PRN232',
        classCode: 'SE1920',
      );
      expect(resolved, isEmpty);
    });
  });
}
