import 'dart:io';
import 'package:excel/excel.dart';

/// Local exporter for attendance records to XLSX and CSV
class ExportService {
  /// Exports selected lessons to CSV with UTF-8 BOM to display Vietnamese characters correctly in Excel
  Future<File> exportToCsv({
    required String filePath,
    required String classCode,
    required List<int> selectedLessonNumbers,
    required List<Map<String, dynamic>> studentsData,
  }) async {
    final buffer = StringBuffer();
    // Prepend UTF-8 BOM (\uFEFF) so Microsoft Excel recognizes UTF-8 encoding
    buffer.write('\uFEFF');

    // Header
    buffer.write('RollNumber,FullName,Email');
    for (final lessonNum in selectedLessonNumbers) {
      final slotLabel = lessonNum.toString().padLeft(2, '0');
      buffer.write(',Slot $slotLabel');
    }
    buffer.writeln();

    // Student rows
    for (final s in studentsData) {
      final roll = s['rollNumber'] ?? '';
      final name = (s['fullName'] ?? '').toString().replaceAll('"', '""');
      final email = s['email'] ?? '';
      buffer.write('$roll,"$name",$email');
      for (final lessonNum in selectedLessonNumbers) {
        final result = s['lesson_$lessonNum'] ?? '';
        buffer.write(',$result');
      }
      buffer.writeln();
    }

    final file = File(filePath);
    return file.writeAsString(buffer.toString());
  }

  /// Exports selected lessons to XLSX format (native Excel workbook)
  Future<File> exportToXlsx({
    required String filePath,
    required String classCode,
    required List<int> selectedLessonNumbers,
    required List<Map<String, dynamic>> studentsData,
  }) async {
    final excel = Excel.createExcel();
    final sheetName = classCode.isNotEmpty ? classCode : 'Attendance';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    // Header row
    final headers = <CellValue>[
      TextCellValue('RollNumber'),
      TextCellValue('FullName'),
      TextCellValue('Email'),
    ];
    for (final lessonNum in selectedLessonNumbers) {
      final slotLabel = lessonNum.toString().padLeft(2, '0');
      headers.add(TextCellValue('Slot $slotLabel'));
    }
    sheet.appendRow(headers);

    // Data rows
    for (final s in studentsData) {
      final row = <CellValue>[
        TextCellValue(s['rollNumber']?.toString() ?? ''),
        TextCellValue(s['fullName']?.toString() ?? ''),
        TextCellValue(s['email']?.toString() ?? ''),
      ];
      for (final lessonNum in selectedLessonNumbers) {
        final result = s['lesson_$lessonNum']?.toString() ?? '';
        row.add(TextCellValue(result));
      }
      sheet.appendRow(row);
    }

    final fileBytes = excel.save();
    final file = File(filePath);
    if (fileBytes != null) {
      await file.writeAsBytes(fileBytes);
    }
    return file;
  }
}
