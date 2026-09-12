import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/export/export_report_service.dart';

void main() {
  test('Kiểm thử xuất báo cáo XLSX và CSV', () async {
    final service = ExportReportService();
    final sampleRoster = [
      {'rollNumber': 'SE182346', 'fullName': 'Trần Gia Bảo', 'email': 'baotg@fpt.edu.vn', 'memberCode': 'BaoTG'},
      {'rollNumber': 'SE193416', 'fullName': 'Nguyễn Ngọc Bảo Cường', 'email': 'cuongnnb@fpt.edu.vn', 'memberCode': 'CuongNNB'},
    ];

    final attendanceData = {
      'baotg@fpt.edu.vn': {1: 'P', 2: 'A', 3: 'P'},
      'cuongnnb@fpt.edu.vn': {1: 'A', 2: 'A', 3: 'A'},
    };

    final tempDir = Directory.systemTemp;
    final csvPath = '${tempDir.path}/test_report.csv';
    final xlsxPath = '${tempDir.path}/test_report.xlsx';

    // 1. Test xuất CSV
    final csvResult = await service.exportToCsv(
      subjectCode: 'PRM393',
      className: 'SE1917',
      roster: sampleRoster,
      selectedLessonNumbers: [1, 2, 3],
      lessonDates: {1: '2026-09-10', 2: '2026-09-13', 3: '2026-09-17'},
      attendanceData: attendanceData,
      targetFilePath: csvPath,
    );

    expect(csvResult.success, isTrue);
    expect(File(csvPath).existsSync(), isTrue);

    // 2. Test xuất XLSX
    final xlsxResult = await service.exportToExcel(
      subjectCode: 'PRM393',
      className: 'SE1917',
      semester: 'FA26',
      roster: sampleRoster,
      selectedLessonNumbers: [1, 2, 3],
      lessonDates: {1: '2026-09-10', 2: '2026-09-13', 3: '2026-09-17'},
      attendanceData: attendanceData,
      targetFilePath: xlsxPath,
    );

    expect(xlsxResult.success, isTrue);
    expect(File(xlsxPath).existsSync(), isTrue);

    // Dọn file tạm
    File(csvPath).deleteSync();
    File(xlsxPath).deleteSync();
  });
}
