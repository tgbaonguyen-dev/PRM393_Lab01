import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:xml/xml.dart';
import '../models/markbook_data.dart';

class ParsedSheetResult {
  final String sheetName;
  final String scheduleCode; // e.g. "12"
  final String subjectCode;  // e.g. "PRM393"
  final String className;    // e.g. "SE1917"
  final int detectedSlotCount; // detected from Slot columns or default
  final List<RosterStudent> roster;
  final List<String> warnings;
  final List<String> errors;

  ParsedSheetResult({
    required this.sheetName,
    required this.scheduleCode,
    required this.subjectCode,
    required this.className,
    required this.detectedSlotCount,
    required this.roster,
    this.warnings = const [],
    this.errors = const [],
  });
}

class MarkbookParser {
  /// Parses an .xlsx or .ods file and returns a list of ParsedSheetResult
  Future<List<ParsedSheetResult>> parseFile(File file) async {
    final bytes = await file.readAsBytes();
    final lowerPath = file.path.toLowerCase();

    if (lowerPath.endsWith('.ods')) {
      return parseOds(bytes);
    } else if (lowerPath.endsWith('.xlsx')) {
      return parseXlsx(bytes);
    } else {
      throw FormatException('Định dạng tệp không được hỗ trợ (chỉ chấp nhận .xlsx và .ods)');
    }
  }

  /// Parses OpenDocument Spreadsheet (.ods) bytes
  List<ParsedSheetResult> parseOds(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final contentXmlFile = archive.findFile('content.xml');

    if (contentXmlFile == null) {
      throw FormatException('Tệp .ods không hợp lệ (không tìm thấy content.xml)');
    }

    final xmlStr = utf8.decode(contentXmlFile.content as List<int>);
    final document = XmlDocument.parse(xmlStr);

    final results = <ParsedSheetResult>[];
    final tables = document.findAllElements('table:table');

    for (final table in tables) {
      final sheetName = table.getAttribute('table:name') ?? '';
      if (sheetName.isEmpty) continue;

      final rowsData = <List<String>>[];
      final rows = table.findElements('table:table-row');

      for (final row in rows) {
        final cellsData = <String>[];
        final cells = row.findElements('table:table-cell');

        for (final cell in cells) {
          final repStr = cell.getAttribute('table:number-columns-repeated');
          final repeat = repStr != null ? int.tryParse(repStr) ?? 1 : 1;
          if (repeat > 100) continue; // Skip trailing empty columns

          final textElements = cell.findAllElements('text:p');
          final text = textElements.map((e) => e.innerText).join(' ').trim();

          for (var i = 0; i < repeat; i++) {
            cellsData.add(text);
          }
        }
        // Remove trailing empty cells in row
        while (cellsData.isNotEmpty && cellsData.last.isEmpty) {
          cellsData.removeLast();
        }
        if (cellsData.isNotEmpty) {
          rowsData.add(cellsData);
        }
      }

      if (rowsData.isNotEmpty) {
        final parsed = _processRawSheetData(sheetName, rowsData);
        results.add(parsed);
      }
    }

    return results;
  }

  /// Parses Excel (.xlsx) bytes
  List<ParsedSheetResult> parseXlsx(Uint8List bytes) {
    final excel = excel_pkg.Excel.decodeBytes(bytes);
    final results = <ParsedSheetResult>[];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;

      final rowsData = <List<String>>[];
      for (final row in sheet.rows) {
        final cellsData = <String>[];
        for (final cell in row) {
          cellsData.add(cell?.value?.toString().trim() ?? '');
        }
        while (cellsData.isNotEmpty && cellsData.last.isEmpty) {
          cellsData.removeLast();
        }
        if (cellsData.isNotEmpty) {
          rowsData.add(cellsData);
        }
      }

      if (rowsData.isNotEmpty) {
        final parsed = _processRawSheetData(table, rowsData);
        results.add(parsed);
      }
    }

    return results;
  }

  /// Extracts metadata, headers, roster, and detected slot count from raw 2D string grid
  ParsedSheetResult _processRawSheetData(String sheetName, List<List<String>> rows) {
    final warnings = <String>[];
    final errors = <String>[];

    // 1. Metadata from Sheet Name (e.g. "12_PRM393_SE1917" or "23_PRM232")
    final nameParts = sheetName.split('_');
    String scheduleCode = nameParts.isNotEmpty ? nameParts[0].trim() : '';
    String subjectCode = nameParts.length > 1 ? nameParts[1].trim() : '';
    String className = nameParts.length > 2 ? nameParts[2].trim() : '';

    if (!RegExp(r'^[123][1234]$').hasMatch(scheduleCode)) {
      warnings.add('Schedule code "$scheduleCode" không khớp mẫu quy ước (1X, 2X, 3X).');
    }

    // 2. Identify header row (contains 'Class', 'RollNumber', 'Email', etc.)
    int headerRowIndex = -1;
    final headerMap = <String, int>{};

    for (var r = 0; r < rows.length && r < 5; r++) {
      final row = rows[r];
      final colIndexMap = <String, int>{};
      for (var c = 0; c < row.length; c++) {
        final normHeader = row[c].replaceAll(' ', '').toLowerCase();
        colIndexMap[normHeader] = c;
      }
      if (colIndexMap.containsKey('rollnumber') || colIndexMap.containsKey('email')) {
        headerRowIndex = r;
        headerMap.addAll(colIndexMap);
        break;
      }
    }

    if (headerRowIndex == -1) {
      errors.add('Không tìm thấy dòng tiêu đề chứa RollNumber hoặc Email.');
      return ParsedSheetResult(
        sheetName: sheetName,
        scheduleCode: scheduleCode,
        subjectCode: subjectCode,
        className: className,
        detectedSlotCount: 20,
        roster: [],
        errors: errors,
      );
    }

    // Check detected slot count from headers (e.g. 'Slot 01' ... 'Slot N')
    final headerRow = rows[headerRowIndex];
    int slotColumnsCount = 0;
    final slotPattern = RegExp(r'^slot\s*\d+$|^lesson\s*\d+$', caseSensitive: false);
    for (final colHeader in headerRow) {
      if (slotPattern.hasMatch(colHeader.trim())) {
        slotColumnsCount++;
      }
    }

    // If slot columns are present in markbook, use that count; otherwise default to 20
    final finalSlotCount = slotColumnsCount > 0 ? slotColumnsCount : 20;

    // 3. Extract student roster
    final classCol = headerMap['class'] ?? -1;
    final rollCol = headerMap['rollnumber'] ?? -1;
    final emailCol = headerMap['email'] ?? -1;
    final memberCodeCol = headerMap['membercode'] ?? -1;
    final nameCol = headerMap['fullname'] ?? -1;

    final roster = <RosterStudent>[];
    final seenEmails = <String>{};
    final seenRolls = <String>{};

    for (var r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];

      String studentClass = classCol >= 0 && classCol < row.length ? row[classCol] : className;
      String rollNumber = rollCol >= 0 && rollCol < row.length ? row[rollCol] : '';
      String email = emailCol >= 0 && emailCol < row.length ? row[emailCol].toLowerCase().trim() : '';
      String memberCode = memberCodeCol >= 0 && memberCodeCol < row.length ? row[memberCodeCol] : '';
      String fullName = nameCol >= 0 && nameCol < row.length ? row[nameCol] : '';

      if (rollNumber.isEmpty && email.isEmpty) {
        continue; // Skip empty rows
      }

      if (className.isEmpty && studentClass.isNotEmpty) {
        className = studentClass;
      }

      // Check duplicates
      if (seenRolls.contains(rollNumber)) {
        warnings.add('Trùng mã sinh viên trong lớp: $rollNumber');
      } else {
        seenRolls.add(rollNumber);
      }

      if (seenEmails.contains(email)) {
        warnings.add('Trùng email trong lớp: $email');
      } else {
        seenEmails.add(email);
      }

      roster.add(RosterStudent(
        rollNumber: rollNumber,
        fullName: fullName,
        email: email,
        memberCode: memberCode.isNotEmpty ? memberCode : null,
        className: studentClass.isNotEmpty ? studentClass : className,
      ));
    }

    return ParsedSheetResult(
      sheetName: sheetName,
      scheduleCode: scheduleCode,
      subjectCode: subjectCode,
      className: className,
      detectedSlotCount: finalSlotCount,
      roster: roster,
      warnings: warnings,
      errors: errors,
    );
  }
}
