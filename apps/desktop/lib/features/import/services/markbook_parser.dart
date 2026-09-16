import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as excel_package;
import 'package:xml/xml.dart';

import '../../schedule/services/schedule_code_parser.dart';
import '../models/import_models.dart';

class MarkbookParser {
  static const requiredHeaders = <String, String>{
    'class': 'Class',
    'rollnumber': 'RollNumber',
    'fullname': 'FullName',
    'email': 'Email',
    'membercode': 'MemberCode',
  };

  Future<WorkbookImportResult> parseFile(File file) async {
    if (!await file.exists()) {
      throw ArgumentError('Không tìm thấy tệp đã chọn.');
    }
    final extension = file.path.split('.').last.toLowerCase();
    return parseBytes(
      bytes: await file.readAsBytes(),
      extension: extension,
      sourceFileName: file.uri.pathSegments.last,
    );
  }

  WorkbookImportResult parseBytes({
    required Uint8List bytes,
    required String extension,
    required String sourceFileName,
  }) {
    final sheets = switch (extension.toLowerCase()) {
      'xlsx' => _readXlsx(bytes),
      'ods' => _readOds(bytes),
      _ => throw const FormatException('Chỉ hỗ trợ tệp .xlsx và .ods.'),
    };

    return WorkbookImportResult(
      sourceFileName: sourceFileName,
      classes: sheets.map(_processSheet).toList(growable: false),
    );
  }

  List<_RawSheet> _readXlsx(Uint8List bytes) {
    final workbook = excel_package.Excel.decodeBytes(bytes);
    return workbook.tables.entries.map((entry) {
      final rows = entry.value.rows.map((row) {
        return row.map((cell) => cell?.value?.toString().trim() ?? '').toList();
      }).toList();
      return _RawSheet(entry.key, rows);
    }).toList();
  }

  List<_RawSheet> _readOds(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final contentFile = archive.findFile('content.xml');
    if (contentFile == null) {
      throw const FormatException('Tệp ODS không hợp lệ: thiếu content.xml.');
    }

    final document = XmlDocument.parse(
      utf8.decode(contentFile.content as List<int>),
    );
    final sheets = <_RawSheet>[];

    for (final table in document.findAllElements('table:table')) {
      final sheetName = table.getAttribute('table:name')?.trim() ?? '';
      if (sheetName.isEmpty) continue;
      final rows = <List<String>>[];

      for (final row in table.findElements('table:table-row')) {
        final values = <String>[];
        for (final cell in row.childElements.where(
          (element) =>
              element.name.qualified == 'table:table-cell' ||
              element.name.qualified == 'table:covered-table-cell',
        )) {
          final repeat =
              int.tryParse(
                cell.getAttribute('table:number-columns-repeated') ?? '1',
              ) ??
              1;
          final paragraphs = cell.findAllElements('text:p');
          var value = paragraphs
              .map((element) => element.innerText)
              .join(' ')
              .trim();
          value = value.isNotEmpty
              ? value
              : (cell.getAttribute('office:string-value') ??
                        cell.getAttribute('office:value') ??
                        '')
                    .trim();

          if (repeat > 512 && value.isEmpty) continue;
          for (var index = 0; index < repeat.clamp(1, 512); index++) {
            values.add(value);
          }
        }
        while (values.isNotEmpty && values.last.isEmpty) {
          values.removeLast();
        }

        final rowRepeat =
            int.tryParse(
              row.getAttribute('table:number-rows-repeated') ?? '1',
            ) ??
            1;
        if (values.isEmpty && rowRepeat > 1) continue;
        for (var index = 0; index < rowRepeat.clamp(1, 500); index++) {
          rows.add(List<String>.of(values));
        }
      }
      sheets.add(_RawSheet(sheetName, rows));
    }
    return sheets;
  }

  ImportedClass _processSheet(_RawSheet sheet) {
    final issues = <ImportValidationIssue>[];
    final metadata = _metadataFromSheetName(sheet.name);
    final scheduleCode = metadata.$1;
    final subjectCode = metadata.$2;
    final sheetClassCode = metadata.$3;

    if (ScheduleCodeParser.tryParse(scheduleCode) == null) {
      issues.add(
        _error(
          sheet.name,
          'invalid_schedule_code',
          'Không đọc được mã lịch từ tên sheet. Giảng viên cần sửa trước khi tiếp tục.',
          field: 'ScheduleCode',
        ),
      );
    }
    if (subjectCode.isEmpty) {
      issues.add(
        _error(
          sheet.name,
          'missing_subject_code',
          'Không đọc được mã môn từ tên sheet.',
          field: 'SubjectCode',
        ),
      );
    }

    if (sheet.rows.isEmpty) {
      issues.add(_error(sheet.name, 'empty_sheet', 'Sheet không có dữ liệu.'));
      return ImportedClass(
        sourceSheetName: sheet.name,
        scheduleCode: scheduleCode,
        subjectCode: subjectCode,
        classCode: sheetClassCode,
        lessonCount: ImportedClass.defaultLessonCountFor(subjectCode),
        students: const [],
        issues: issues,
      );
    }

    final headerResult = _findHeader(sheet.rows);
    if (headerResult == null) {
      issues.add(
        _error(
          sheet.name,
          'header_not_found',
          'Không tìm thấy dòng tiêu đề Markbook trong 10 dòng đầu.',
        ),
      );
      return ImportedClass(
        sourceSheetName: sheet.name,
        scheduleCode: scheduleCode,
        subjectCode: subjectCode,
        classCode: sheetClassCode,
        lessonCount: ImportedClass.defaultLessonCountFor(subjectCode),
        students: const [],
        issues: issues,
      );
    }

    final headerRowIndex = headerResult.$1;
    final headerMap = headerResult.$2;
    for (final entry in requiredHeaders.entries) {
      if (!headerMap.containsKey(entry.key)) {
        issues.add(
          _error(
            sheet.name,
            'missing_header',
            'Thiếu cột bắt buộc ${entry.value}.',
            rowNumber: headerRowIndex + 1,
            field: entry.value,
          ),
        );
      }
    }

    final students = <ImportedStudent>[];
    final seenRollNumbers = <String, int>{};
    final seenEmails = <String, int>{};

    for (
      var rowIndex = headerRowIndex + 1;
      rowIndex < sheet.rows.length;
      rowIndex++
    ) {
      final row = sheet.rows[rowIndex];
      if (row.every((value) => value.trim().isEmpty)) continue;

      String valueFor(String header) {
        final column = headerMap[header];
        return column != null && column < row.length ? row[column].trim() : '';
      }

      final classCode = valueFor('class');
      final rollNumber = valueFor('rollnumber');
      final fullName = valueFor('fullname');
      final email = valueFor('email');
      final memberCode = valueFor('membercode');
      final values = [classCode, rollNumber, fullName, email, memberCode];
      if (values.every((value) => value.isEmpty)) continue;

      final rowNumber = rowIndex + 1;
      final fields = <String, String>{
        'Class': classCode,
        'RollNumber': rollNumber,
        'FullName': fullName,
        'Email': email,
        'MemberCode': memberCode,
      };
      for (final entry in fields.entries) {
        if (entry.value.isEmpty) {
          issues.add(
            _error(
              sheet.name,
              'missing_value',
              'Dòng $rowNumber thiếu ${entry.key}.',
              rowNumber: rowNumber,
              field: entry.key,
            ),
          );
        }
      }

      final normalizedRollNumber = rollNumber.toUpperCase();
      final normalizedEmail = email.toLowerCase();
      if (normalizedEmail.isNotEmpty &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
        issues.add(
          _error(
            sheet.name,
            'invalid_email',
            'Email $email không đúng định dạng.',
            rowNumber: rowNumber,
            field: 'Email',
          ),
        );
      }
      if (normalizedRollNumber.isNotEmpty) {
        final firstRow = seenRollNumbers[normalizedRollNumber];
        if (firstRow != null) {
          issues.add(
            _warning(
              sheet.name,
              'duplicate_roll_number',
              'RollNumber $rollNumber trùng với dòng $firstRow.',
              rowNumber: rowNumber,
              field: 'RollNumber',
            ),
          );
        } else {
          seenRollNumbers[normalizedRollNumber] = rowNumber;
        }
      }
      if (normalizedEmail.isNotEmpty) {
        final firstRow = seenEmails[normalizedEmail];
        if (firstRow != null) {
          issues.add(
            _warning(
              sheet.name,
              'duplicate_email',
              'Email $email trùng với dòng $firstRow.',
              rowNumber: rowNumber,
              field: 'Email',
            ),
          );
        } else {
          seenEmails[normalizedEmail] = rowNumber;
        }
      }

      students.add(
        ImportedStudent(
          classCode: classCode,
          rollNumber: rollNumber,
          fullName: fullName,
          email: normalizedEmail,
          memberCode: memberCode,
        ),
      );
    }

    final rosterClasses = students
        .map((student) => student.classCode.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    var resolvedClassCode = sheetClassCode;
    if (resolvedClassCode.isEmpty && rosterClasses.length == 1) {
      resolvedClassCode = rosterClasses.single;
    }
    if (rosterClasses.length > 1) {
      issues.add(
        _error(
          sheet.name,
          'multiple_classes',
          'Một sheet chứa nhiều mã lớp: ${rosterClasses.join(', ')}.',
          field: 'Class',
        ),
      );
    } else if (sheetClassCode.isNotEmpty &&
        rosterClasses.isNotEmpty &&
        !rosterClasses.contains(sheetClassCode.toUpperCase())) {
      issues.add(
        _error(
          sheet.name,
          'class_conflict',
          'Mã lớp trong tên sheet ($sheetClassCode) khác cột Class (${rosterClasses.single}).',
          field: 'Class',
        ),
      );
    }
    if (students.isEmpty) {
      issues.add(
        _error(sheet.name, 'empty_roster', 'Sheet không có sinh viên hợp lệ.'),
      );
    }

    return ImportedClass(
      sourceSheetName: sheet.name,
      scheduleCode: scheduleCode,
      subjectCode: subjectCode,
      classCode: resolvedClassCode,
      lessonCount: ImportedClass.defaultLessonCountFor(subjectCode),
      students: students,
      issues: issues,
    );
  }

  (int, Map<String, int>)? _findHeader(List<List<String>> rows) {
    for (
      var rowIndex = 0;
      rowIndex < rows.length && rowIndex < 10;
      rowIndex++
    ) {
      final map = <String, int>{};
      for (
        var columnIndex = 0;
        columnIndex < rows[rowIndex].length;
        columnIndex++
      ) {
        final normalized = _normalizeHeader(rows[rowIndex][columnIndex]);
        if (requiredHeaders.containsKey(normalized)) {
          map[normalized] = columnIndex;
        }
      }
      if (map.containsKey('rollnumber') || map.containsKey('email')) {
        return (rowIndex, map);
      }
    }
    return null;
  }

  static String _normalizeHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  static (String, String, String) _metadataFromSheetName(String sheetName) {
    final parts = sheetName.trim().split('_');
    return (
      parts.isNotEmpty ? parts[0].trim() : '',
      parts.length > 1 ? parts[1].trim().toUpperCase() : '',
      parts.length > 2 ? parts.sublist(2).join('_').trim().toUpperCase() : '',
    );
  }

  static ImportValidationIssue _error(
    String sheetName,
    String code,
    String message, {
    int? rowNumber,
    String? field,
  }) => ImportValidationIssue(
    severity: ValidationSeverity.error,
    code: code,
    message: message,
    sheetName: sheetName,
    rowNumber: rowNumber,
    field: field,
  );

  static ImportValidationIssue _warning(
    String sheetName,
    String code,
    String message, {
    int? rowNumber,
    String? field,
  }) => ImportValidationIssue(
    severity: ValidationSeverity.warning,
    code: code,
    message: message,
    sheetName: sheetName,
    rowNumber: rowNumber,
    field: field,
  );
}

class _RawSheet {
  final String name;
  final List<List<String>> rows;

  const _RawSheet(this.name, this.rows);
}
