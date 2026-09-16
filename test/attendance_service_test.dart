import 'dart:io';

import 'package:test/test.dart';

import '../backend/lib/services/attendance_service.dart';
import '../backend/lib/repositories/sheets_repository.dart';

void main() {
  late SheetsRepository repository;
  late AttendanceService attendanceService;

  const testSessionId = 'PRM393_SE1917_Lesson_1';
  final gatewayUrl =
      Platform.environment['APPS_SCRIPT_GATEWAY_URL'] ??
      'https://script.google.com/macros/s/AKfycbxuAV49xcKSzJHeiyRZ96LEj_qwLLP_omiJu5XTXbCo-xdRg0G7KhE9SNZI_y28r21ftw/exec';

  setUpAll(() async {
    repository = SheetsRepository(gatewayUrl: gatewayUrl);
    attendanceService = AttendanceService(sheetsRepository: repository);

    // 1. Đồng bộ tạo Sheet mẫu và mở ca nếu chưa có
    final sampleStudents = [
      {
        'rollNumber': 'SE182346',
        'fullName': 'Trần Gia Bảo',
        'email': 'baotgse182346@fpt.edu.vn',
      },
      {
        'rollNumber': 'SE193416',
        'fullName': 'Nguyễn Ngọc Bảo Cường',
        'email': 'cuongnnbse193416@fpt.edu.vn',
      },
      {
        'rollNumber': 'SE190507',
        'fullName': 'Ngô Chí Nam',
        'email': 'namncse190507@fpt.edu.vn',
      },
    ];

    await repository.syncAllClasses(
      classes: [
        {
          'className': 'SE1917',
          'subjectCode': 'PRM393',
          'scheduleCode': '12',
          'slotCount': 20,
          'lessons': List.generate(
            20,
            (i) => {'sequenceNumber': i + 1, 'date': '2026-09-14'},
          ),
          'roster': sampleStudents,
        },
      ],
      startDate: '2026-09-07',
    );

    // Mở ca điểm danh Lesson 1 (khởi tạo toàn bộ thành A)
    await repository.openAttendanceWindow(testSessionId);
  });

  group('Kiểm thử Live Google Sheets (Thành viên 4)', () {
    test(
      '1. Giảng viên sửa thủ công bạn Trần Gia Bảo thành P (Xanh lá)',
      () async {
        const testEmail = 'baotgse182346@fpt.edu.vn';

        print('⏳ Đang gửi lệnh đổi $testEmail thành "P"...');
        final success = await attendanceService.manualOverride(
          sessionId: testSessionId,
          studentEmail: testEmail,
          status: 'P',
        );

        expect(success, isTrue);
        print(
          '🟢 ĐÃ ĐỔI THÀNH CÔNG THÀNH "P"! Hãy F5 Google Sheet để xem ô Slot 01 đổi màu xanh lá.',
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    test('2. Backend đọc lại sĩ số mới từ Google Sheet', () async {
      // Đợi 2 giây để Google Sheet cập nhật
      await Future.delayed(const Duration(seconds: 2));

      final result = await attendanceService.getAttendanceSummary(
        testSessionId,
      );

      print('📊 Sĩ số thực tế vừa đọc về từ Google Sheet:');
      print('   - Tổng số SV: ${result['summary']['total']}');
      print('   - Có mặt (P): ${result['summary']['present']} (Phải là 1)');
      print('   - Vắng (A): ${result['summary']['absent']}');

      expect(result['summary']['present'], greaterThanOrEqualTo(1));
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
