import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/export/services/export_service.dart';

void main() {
  test('ExportService writes UTF-8 BOM and correct student names to CSV', () async {
    final exportService = ExportService();
    const filePath = 'test_attendance_utf8.csv';

    final students = [
      {
        'rollNumber': 'SE193416',
        'fullName': 'Nguyễn Ngọc Bảo Cường',
        'email': 'firephoenix0304@gmail.com',
        'lesson_1': 'P',
      },
      {
        'rollNumber': 'SE184226',
        'fullName': 'Lâm Hoàng Nhân',
        'email': 'nhanlhse184226@fpt.edu.vn',
        'lesson_1': 'A',
      },
    ];

    final file = await exportService.exportToCsv(
      filePath: filePath,
      classCode: 'SE1917',
      selectedLessonNumbers: [1, 2],
      studentsData: students,
    );

    expect(file.existsSync(), isTrue);

    // Verify first 3 bytes are UTF-8 BOM (0xEF, 0xBB, 0xBF)
    final bytes = await file.readAsBytes();
    expect(bytes[0], equals(0xEF));
    expect(bytes[1], equals(0xBB));
    expect(bytes[2], equals(0xBF));

    final content = await file.readAsString();
    expect(content.contains('Nguyễn Ngọc Bảo Cường'), isTrue);
    expect(content.contains('Lâm Hoàng Nhân'), isTrue);

    // Clean up test file
    await file.delete();
  });

  test('ExportService exports native XLSX workbook', () async {
    final exportService = ExportService();
    const filePath = 'test_attendance.xlsx';

    final students = [
      {
        'rollNumber': 'SE193416',
        'fullName': 'Nguyễn Ngọc Bảo Cường',
        'email': 'firephoenix0304@gmail.com',
        'lesson_1': 'P',
      },
    ];

    final file = await exportService.exportToXlsx(
      filePath: filePath,
      classCode: 'SE1917',
      selectedLessonNumbers: [1],
      studentsData: students,
    );

    expect(file.existsSync(), isTrue);
    expect(file.lengthSync() > 0, isTrue);

    // Clean up
    await file.delete();
  });

  test('ExportService supports exporting 20 slots with Slot 1 and 2 attendance', () async {
    final exportService = ExportService();
    const filePath = 'test_attendance_20slots.csv';

    final students = [
      {
        'rollNumber': 'SE193416',
        'fullName': 'Nguyễn Ngọc Bảo Cường',
        'email': 'firephoenix0304@gmail.com',
        'lesson_1': 'P',
        'lesson_2': 'P',
      },
      {
        'rollNumber': 'SE184226',
        'fullName': 'Lâm Hoàng Nhân',
        'email': 'nhanlhse184226@fpt.edu.vn',
        'lesson_1': 'A',
        'lesson_2': 'P',
      },
    ];

    final all20Slots = List.generate(20, (i) => i + 1);
    final file = await exportService.exportToCsv(
      filePath: filePath,
      classCode: 'SE1920',
      selectedLessonNumbers: all20Slots,
      studentsData: students,
    );

    expect(file.existsSync(), isTrue);
    final content = await file.readAsString();

    // Verify header has Slot 01 through Slot 20
    expect(content.contains('Slot 01'), isTrue);
    expect(content.contains('Slot 20'), isTrue);

    // Verify row results for Slot 1 and Slot 2
    expect(content.contains('SE193416,"Nguyễn Ngọc Bảo Cường",firephoenix0304@gmail.com,P,P'), isTrue);
    expect(content.contains('SE184226,"Lâm Hoàng Nhân",nhanlhse184226@fpt.edu.vn,A,P'), isTrue);

    await file.delete();
  });
}
