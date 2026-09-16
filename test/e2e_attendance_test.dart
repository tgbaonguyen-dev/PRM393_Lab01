import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../backend/lib/repositories/sheets_repository.dart';

/// Kịch bản kiểm thử tích hợp End-to-End (E2E) với Google Sheets Markbook (M5)
/// Kiểm thử đồng bộ các lớp học, 20 Slot điểm danh, cập nhật Realtime vào từng ô
void main() {
  late SheetsRepository repository;
  late List<Map<String, dynamic>> sampleStudents;

  const testSessionId = 'PRM393_SE1917_Lesson_1';
  final gatewayUrl = Platform.environment['APPS_SCRIPT_GATEWAY_URL'] ??
      'https://script.google.com/macros/s/AKfycbxuAV49xcKSzJHeiyRZ96LEj_qwLLP_omiJu5XTXbCo-xdRg0G7KhE9SNZI_y28r21ftw/exec';

  setUpAll(() {
    repository = SheetsRepository(gatewayUrl: gatewayUrl);

    // Đọc 5 tài khoản mẫu từ database/seed_students.json
    final seedFile = File('database/seed_students.json');
    if (seedFile.existsSync()) {
      final jsonStr = seedFile.readAsStringSync();
      final list = jsonDecode(jsonStr) as List;
      sampleStudents = list.cast<Map<String, dynamic>>();
    } else {
      sampleStudents = [
        {'rollNumber': 'SE182346', 'fullName': 'Trần Gia Bảo', 'email': 'baotgse182346@fpt.edu.vn'},
        {'rollNumber': 'SE193416', 'fullName': 'Nguyễn Ngọc Bảo Cường', 'email': 'cuongnnbse193416@fpt.edu.vn'},
        {'rollNumber': 'SE190507', 'fullName': 'Ngô Chí Nam', 'email': 'namncse190507@fpt.edu.vn'},
        {'rollNumber': 'SE193445', 'fullName': 'Ngô Tấn Thành', 'email': 'thanhntse193445@fpt.edu.vn'},
        {'rollNumber': 'SE172145', 'fullName': 'Nguyễn Mai Hào Thiên', 'email': 'thiennmhse172145@fpt.edu.vn'},
      ];
    }
  });

  group('Kiểm thử Google Sheets Class Markbooks & Realtime Cell Update (M5)', () {
    test('1. Đồng bộ tạo Tab Overview và Sheet riêng cho Lớp học (20 Slot điểm danh)', () async {
      final sampleClass = {
        'className': 'SE1917',
        'subjectCode': 'PRM393',
        'scheduleCode': '12',
        'slotCount': 20,
        'lessons': List.generate(20, (i) => {
          'sequenceNumber': i + 1,
          'date': '2026-09-${(10 + i).toString().padLeft(2, '0')}'
        }),
        'roster': sampleStudents,
      };

      final result = await repository.syncAllClasses(
        classes: [sampleClass],
        startDate: '2026-09-07',
      );

      expect(result['success'], isTrue, reason: 'Phải tạo thành công Tab Overview và Sheet lớp học');
      expect(result['spreadsheetUrl'], isNotNull);
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('2. Mở ca điểm danh Slot 01: Khởi tạo toàn bộ ô thành A (Vắng)', () async {
      final window = await repository.openAttendanceWindow(testSessionId);
      expect(window, isNotNull);
      expect(window?['isOpen'], isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('3. Sinh viên quét QR check-in: Cập nhật ô Slot 01 thành P (Xanh lá)', () async {
      final student1 = sampleStudents[0]['email'] as String;
      final res = await repository.recordCheckIn(testSessionId, student1);

      expect(res['success'], isTrue, reason: 'Phải ghi nhận điểm danh P thành công vào ô Slot');
      final data = res['data'];
      final status = (data is Map<String, dynamic>) ? data['status'] : res['status'];
      expect(status, equals('P'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('4. Giảng viên sửa tay thành A (Đỏ): Cập nhật ô Realtime tức thì', () async {
      final student1 = sampleStudents[0]['email'] as String;
      final overrideSuccess = await repository.recordManualOverride(testSessionId, student1, 'A');
      expect(overrideSuccess, isTrue, reason: 'Giảng viên sửa tay A phải cập nhật ô Slot thành A');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('5. Đóng ca điểm danh', () async {
      final activeWin = await repository.getActiveWindow(testSessionId);
      expect(activeWin, isNotNull);

      final closed = await repository.closeAttendanceWindow(activeWin!['id'] as String);
      expect(closed, isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
