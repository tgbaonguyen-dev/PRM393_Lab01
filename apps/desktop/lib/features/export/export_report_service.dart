import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';

/// Kết quả xuất báo cáo điểm danh
class ExportResult {
  final bool success;
  final String filePath;
  final int studentCount;
  final int lessonCount;
  final String? error;

  ExportResult({
    required this.success,
    required this.filePath,
    required this.studentCount,
    required this.lessonCount,
    this.error,
  });
}

/// Dịch vụ xuất báo cáo điểm danh ra file .xlsx và .csv lưu cục bộ trên máy Giảng viên
/// Đáp ứng các yêu cầu SRS v4.0: FR-22, FR-23, FR-24, FR-25, AC-12
class ExportReportService {
  /// Xuất báo cáo ra file Excel (.xlsx) với định dạng bảng chuyên nghiệp
  Future<ExportResult> exportToExcel({
    required String subjectCode,
    required String className,
    required String semester,
    required List<Map<String, dynamic>> roster,
    required List<int> selectedLessonNumbers,
    required Map<int, String> lessonDates,
    required Map<String, Map<int, String>>
    attendanceData, // email -> {lessonNumber: status}
    required String targetFilePath,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheetName = '${subjectCode}_$className';
      final Sheet sheet = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      // Xóa sheet mặc định 'Sheet1' nếu có
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final sortedLessons = List<int>.from(selectedLessonNumbers)..sort();

      // 1. Dòng 1: Tiêu đề báo cáo
      final totalCols = 5 + sortedLessons.length + 3;
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: 0),
      );

      final titleCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      );
      titleCell.value = TextCellValue(
        'BÁO CÁO ĐIỂM DANH - MÔN: $subjectCode | LỚP: $className | HỌC KỲ: $semester',
      );
      titleCell.cellStyle = CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1E3A8A'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // 2. Dòng 2: Tiêu đề các cột
      final headers = <String>[
        'STT',
        'MSSV',
        'Họ và tên',
        'Email FPT',
        'Mã FAP',
      ];

      for (final lesNum in sortedLessons) {
        final date = lessonDates[lesNum];
        final dateSuffix = date != null && date.isNotEmpty ? '\n($date)' : '';
        final slotLabel =
            'Slot ${lesNum.toString().padLeft(2, '0')}$dateSuffix';
        headers.add(slotLabel);
      }

      headers.add('Tổng Vắng (A)');
      headers.add('Tổng Có mặt (P)');
      headers.add('Tỉ lệ Vắng (%)');

      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1),
        );
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString('#2563EB'),
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
      }

      // 3. Dòng 3..N: Dữ liệu Sinh viên
      for (int r = 0; r < roster.length; r++) {
        final student = roster[r];
        final email = (student['email'] ?? '').toString().trim().toLowerCase();
        final rowIndex = r + 2;

        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
            )
            .value = IntCellValue(
          r + 1,
        );
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
            )
            .value = TextCellValue(
          student['rollNumber']?.toString() ?? '',
        );
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
            )
            .value = TextCellValue(
          student['fullName']?.toString() ?? '',
        );
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
            )
            .value = TextCellValue(
          email,
        );
        sheet
            .cell(
              CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
            )
            .value = TextCellValue(
          student['memberCode']?.toString() ?? '',
        );

        int absentCount = 0;
        int presentCount = 0;

        for (int l = 0; l < sortedLessons.length; l++) {
          final lesNum = sortedLessons[l];
          final status = attendanceData[email]?[lesNum] ?? '';
          final colIndex = 5 + l;
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(
              columnIndex: colIndex,
              rowIndex: rowIndex,
            ),
          );

          if (status == 'P') {
            cell.value = TextCellValue('P');
            presentCount++;
            cell.cellStyle = CellStyle(
              bold: true,
              fontColorHex: ExcelColor.fromHexString('#15803D'),
              backgroundColorHex: ExcelColor.fromHexString('#DCFCE7'),
              horizontalAlign: HorizontalAlign.Center,
            );
          } else if (status == 'A') {
            cell.value = TextCellValue('A');
            absentCount++;
            cell.cellStyle = CellStyle(
              bold: true,
              fontColorHex: ExcelColor.fromHexString('#B91C1C'),
              backgroundColorHex: ExcelColor.fromHexString('#FEE2E2'),
              horizontalAlign: HorizontalAlign.Center,
            );
          } else {
            // Giữ đúng ngữ nghĩa 'Trống' (chưa điểm danh) theo FR-23
            cell.value = TextCellValue('');
            cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
          }
        }

        // Thống kê
        final absentCol = 5 + sortedLessons.length;
        final presentCol = 5 + sortedLessons.length + 1;
        final pctCol = 5 + sortedLessons.length + 2;

        sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: absentCol,
                rowIndex: rowIndex,
              ),
            )
            .value = IntCellValue(
          absentCount,
        );
        sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: presentCol,
                rowIndex: rowIndex,
              ),
            )
            .value = IntCellValue(
          presentCount,
        );

        final absentPct = sortedLessons.isNotEmpty
            ? (absentCount / sortedLessons.length) * 100
            : 0.0;
        final pctCell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: pctCol, rowIndex: rowIndex),
        );
        pctCell.value = TextCellValue('${absentPct.toStringAsFixed(1)}%');

        if (absentPct > 20.0) {
          pctCell.cellStyle = CellStyle(
            bold: true,
            fontColorHex: ExcelColor.fromHexString('#B91C1C'),
            backgroundColorHex: ExcelColor.fromHexString('#FEE2E2'),
            horizontalAlign: HorizontalAlign.Center,
          );
        } else {
          pctCell.cellStyle = CellStyle(
            horizontalAlign: HorizontalAlign.Center,
          );
        }
      }

      // Lưu file ra đĩa
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(targetFilePath);
        await file.create(recursive: true);
        await file.writeAsBytes(fileBytes);

        return ExportResult(
          success: true,
          filePath: targetFilePath,
          studentCount: roster.length,
          lessonCount: sortedLessons.length,
        );
      } else {
        return ExportResult(
          success: false,
          filePath: targetFilePath,
          studentCount: roster.length,
          lessonCount: sortedLessons.length,
          error: 'Không thể mã hóa file Excel.',
        );
      }
    } catch (e) {
      return ExportResult(
        success: false,
        filePath: targetFilePath,
        studentCount: roster.length,
        lessonCount: selectedLessonNumbers.length,
        error: e.toString(),
      );
    }
  }

  /// Xuất báo cáo ra file CSV (UTF-8 với BOM để mở trực tiếp trong Excel không bị lỗi font tiếng Việt)
  /// Tuân thủ quy định FR-23, FR-25
  Future<ExportResult> exportToCsv({
    required String subjectCode,
    required String className,
    required List<Map<String, dynamic>> roster,
    required List<int> selectedLessonNumbers,
    required Map<int, String> lessonDates,
    required Map<String, Map<int, String>> attendanceData,
    required String targetFilePath,
  }) async {
    try {
      final sortedLessons = List<int>.from(selectedLessonNumbers)..sort();
      final buffer = StringBuffer();

      // Thêm UTF-8 BOM (\uFEFF) để Excel hiển thị đúng tiếng Việt
      buffer.write('\uFEFF');

      // 1. Header CSV
      final headers = <String>['STT', 'MSSV', 'Họ và tên', 'Email', 'Mã FAP'];

      for (final lesNum in sortedLessons) {
        final date = lessonDates[lesNum];
        final dateSuffix = date != null && date.isNotEmpty ? ' ($date)' : '';
        final label = 'Slot ${lesNum.toString().padLeft(2, '0')}$dateSuffix';
        headers.add('"$label"');
      }

      headers.add('"Tổng Vắng (A)"');
      headers.add('"Tổng Có mặt (P)"');
      headers.add('"Tỉ lệ Vắng (%)"');

      buffer.writeln(headers.join(','));

      // 2. Data rows
      for (int i = 0; i < roster.length; i++) {
        final student = roster[i];
        final email = (student['email'] ?? '').toString().trim().toLowerCase();
        final row = <String>[
          '${i + 1}',
          '"${student['rollNumber'] ?? ''}"',
          '"${student['fullName'] ?? ''}"',
          '"$email"',
          '"${student['memberCode'] ?? ''}"',
        ];

        int absentCount = 0;
        int presentCount = 0;

        for (final lesNum in sortedLessons) {
          final status = attendanceData[email]?[lesNum] ?? '';
          if (status == 'P') {
            row.add('P');
            presentCount++;
          } else if (status == 'A') {
            row.add('A');
            absentCount++;
          } else {
            row.add(''); // Blank
          }
        }

        final absentPct = sortedLessons.isNotEmpty
            ? (absentCount / sortedLessons.length) * 100
            : 0.0;
        row.add('$absentCount');
        row.add('$presentCount');
        row.add('"${absentPct.toStringAsFixed(1)}%"');

        buffer.writeln(row.join(','));
      }

      final file = File(targetFilePath);
      await file.create(recursive: true);
      await file.writeAsString(buffer.toString(), encoding: utf8);

      return ExportResult(
        success: true,
        filePath: targetFilePath,
        studentCount: roster.length,
        lessonCount: sortedLessons.length,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        filePath: targetFilePath,
        studentCount: roster.length,
        lessonCount: selectedLessonNumbers.length,
        error: e.toString(),
      );
    }
  }
}
