import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/import/services/markbook_import_merger.dart';

void main() {
  test('keeps earlier classes when a different Markbook is imported', () {
    final current = WorkbookImportResult(
      sourceFileName: 'first.xlsx',
      classes: List.generate(
        8,
        (index) => _class('PRM393', 'SE19${index + 10}'),
      ),
    );
    final incoming = WorkbookImportResult(
      sourceFileName: 'second.xlsx',
      classes: [_class('PRN232', 'SE2001')],
    );

    final merged = mergeMarkbookImports(current, incoming);

    expect(merged.classes, hasLength(9));
    expect(merged.classes.first.classCode, 'SE1910');
    expect(merged.classes.last.classCode, 'SE2001');
  });

  test('refreshes a duplicate class instead of adding it twice', () {
    final oldClass = _class('PRM393', 'SE1917', student: 'SE000001');
    final refreshed = _class('prm393', 'se1917', student: 'SE000002');

    final merged = mergeMarkbookImports(
      WorkbookImportResult(sourceFileName: 'old.xlsx', classes: [oldClass]),
      WorkbookImportResult(sourceFileName: 'new.xlsx', classes: [refreshed]),
    );

    expect(merged.classes, hasLength(1));
    expect(merged.classes.single.students.single.rollNumber, 'SE000002');
  });
}

ImportedClass _class(
  String subjectCode,
  String classCode, {
  String student = 'SE123456',
}) => ImportedClass(
  sourceSheetName: 'Sheet1',
  scheduleCode: '12',
  subjectCode: subjectCode,
  classCode: classCode,
  students: [
    ImportedStudent(
      classCode: classCode,
      rollNumber: student,
      fullName: 'Student',
      email: '${student.toLowerCase()}@example.com',
      memberCode: 'M001',
    ),
  ],
  issues: const [],
);
