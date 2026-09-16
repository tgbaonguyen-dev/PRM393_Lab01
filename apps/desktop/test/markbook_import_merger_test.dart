import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/import/services/imported_class_validator.dart';
import 'package:prm393_desktop/features/import/services/markbook_import_merger.dart';

void main() {
  test('keeps eight earlier classes when one new class is imported', () {
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

  test('retains cross-file duplicates so validation can block them', () {
    final merged = mergeMarkbookImports(
      WorkbookImportResult(
        sourceFileName: 'first.xlsx',
        classes: [_class('PRM393', 'SE1920')],
      ),
      WorkbookImportResult(
        sourceFileName: 'second.xlsx',
        classes: [_class('prm393', 'se1920')],
      ),
    );
    final validated = validateDistinctClassOfferings(merged.classes);

    expect(validated, hasLength(2));
    expect(validated.every((item) => item.hasErrors), isTrue);
  });
}

ImportedClass _class(String subjectCode, String classCode) => ImportedClass(
  sourceSheetName: '12_${subjectCode}_$classCode',
  scheduleCode: '12',
  subjectCode: subjectCode,
  classCode: classCode,
  students: const [],
  issues: const [],
);
