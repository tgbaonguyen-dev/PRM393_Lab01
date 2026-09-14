import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/services/markbook_parser.dart';

void main() {
  final parser = MarkbookParser();

  test('parses the five roster columns and ignores grade columns', () {
    final result = parser.parseBytes(
      bytes: _workbookBytes([
        ['Class', 'RollNumber', 'Email', 'MemberCode', 'FullName', 'ExamDate'],
        [
          'SE1917',
          'se123456',
          'Student@Example.com',
          'M001',
          'Nguyen Van A',
          '2026-12-01',
        ],
      ]),
      extension: 'xlsx',
      sourceFileName: 'markbook.xlsx',
    );

    final importedClass = result.classes.single;
    expect(importedClass.scheduleCode, '12');
    expect(importedClass.subjectCode, 'PRM393');
    expect(importedClass.classCode, 'SE1917');
    expect(importedClass.students.single.email, 'student@example.com');
    expect(importedClass.students.single.normalizedRollNumber, 'SE123456');
    expect(importedClass.hasErrors, isFalse);
    expect(importedClass.lessonCount, 20);
  });

  test('defaults PRN subjects to 22 lessons', () {
    final result = parser.parseBytes(
      bytes: _workbookBytes([
        ['Class', 'RollNumber', 'Email', 'MemberCode', 'FullName'],
        ['SE1922', 'SE111111', 'student@example.com', 'M001', 'Student'],
      ], sheetName: '23_PRN232_SE1922'),
      extension: 'xlsx',
      sourceFileName: 'markbook.xlsx',
    );

    expect(result.classes.single.lessonCount, 22);
  });

  test('reports missing columns and duplicate identities', () {
    final result = parser.parseBytes(
      bytes: _workbookBytes([
        ['Class', 'RollNumber', 'Email', 'FullName'],
        ['SE1917', 'SE123456', 'same@example.com', 'Student One'],
        ['SE1917', 'se123456', 'SAME@example.com', 'Student Two'],
        ['SE1917', 'SE999999', 'not-an-email', 'Student Three'],
      ]),
      extension: 'xlsx',
      sourceFileName: 'invalid.xlsx',
    );
    final issues = result.classes.single.issues;

    expect(issues.any((issue) => issue.code == 'missing_header'), isTrue);
    expect(
      issues.any((issue) => issue.code == 'duplicate_roll_number'),
      isTrue,
    );
    expect(issues.any((issue) => issue.code == 'duplicate_email'), isTrue);
    expect(issues.any((issue) => issue.code == 'invalid_email'), isTrue);
  });

  test('takes class code from roster silently when sheet suffix is absent', () {
    final result = parser.parseBytes(
      bytes: _workbookBytes([
        ['Class', 'RollNumber', 'Email', 'MemberCode', 'FullName'],
        ['SE1922', 'SE111111', 'student@gmail.com', 'M001', 'Student'],
      ], sheetName: '23_PRM232'),
      extension: 'xlsx',
      sourceFileName: 'markbook.xlsx',
    );

    expect(result.classes.single.classCode, 'SE1922');
    expect(result.classes.single.issues, isEmpty);
  });

  final realOds = File('../../../FA26_Markbook.ods');
  test(
    'parses the supplied real ODS markbook',
    () async {
      final result = await parser.parseFile(realOds);
      expect(result.classes, hasLength(8));
      expect(result.totalStudents, 282);
      expect(result.classes.every((item) => item.students.isNotEmpty), isTrue);
    },
    skip: realOds.existsSync()
        ? false
        : 'Real Markbook is not available in CI.',
  );
}

Uint8List _workbookBytes(
  List<List<String>> rows, {
  String sheetName = '12_PRM393_SE1917',
}) {
  final workbook = Excel.createExcel();
  final defaultSheet = workbook.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != sheetName) {
    workbook.rename(defaultSheet, sheetName);
  }
  final sheet = workbook[sheetName];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    for (
      var columnIndex = 0;
      columnIndex < rows[rowIndex].length;
      columnIndex++
    ) {
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: columnIndex,
              rowIndex: rowIndex,
            ),
          )
          .value = TextCellValue(
        rows[rowIndex][columnIndex],
      );
    }
  }
  return Uint8List.fromList(workbook.encode()!);
}
