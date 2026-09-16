import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/import/services/imported_class_validator.dart';

void main() {
  test('rejects duplicate subject-code and class-code pairs', () {
    final validated = validateDistinctClassOfferings([
      _class('23_PRM393_SE1920', 'PRM393', 'SE1920'),
      _class('14_PRM393_SE1920', 'prm393', 'se1920'),
    ]);

    expect(
      validated.every(
        (item) => item.issues.any(
          (issue) => issue.code == duplicateOfferingIssueCode && issue.isError,
        ),
      ),
      isTrue,
    );
  });

  test('accepts different class codes for the same subject', () {
    final validated = validateDistinctClassOfferings([
      _class('12_PRM393_SE1917', 'PRM393', 'SE1917'),
      _class('13_PRM393_SE1920', 'PRM393', 'SE1920'),
      _class('14_PRM393_SE1922', 'PRM393', 'SE1922'),
    ]);

    expect(
      validated.expand((item) => item.issues),
      isNot(
        contains(
          predicate<ImportValidationIssue>(
            (issue) => issue.code == duplicateOfferingIssueCode,
          ),
        ),
      ),
    );
  });

  test('clears a previous duplicate error after the code is corrected', () {
    final duplicate = validateDistinctClassOfferings([
      _class('23_PRM393_SE1920', 'PRM393', 'SE1920'),
      _class('14_PRM393_SE1920', 'PRM393', 'SE1920'),
    ]);
    final corrected = validateDistinctClassOfferings([
      duplicate.first,
      duplicate.last.copyWith(classCode: 'SE1922'),
    ]);

    expect(
      corrected.expand((item) => item.issues),
      isNot(
        contains(
          predicate<ImportValidationIssue>(
            (issue) => issue.code == duplicateOfferingIssueCode,
          ),
        ),
      ),
    );
  });

  test('an explicitly corrected class code can be applied to its roster', () {
    final original = _class(
      '14_PRM393_SE1920',
      'PRM393',
      'SE1920',
      withStudent: true,
    );
    const correctedCode = 'SE1922';
    final corrected = original.copyWith(
      classCode: correctedCode,
      students: original.students
          .map((student) => student.copyWith(classCode: correctedCode))
          .toList(),
    );

    expect(corrected.classCode, correctedCode);
    expect(corrected.students.single.classCode, correctedCode);
  });
}

ImportedClass _class(
  String sheetName,
  String subjectCode,
  String classCode, {
  bool withStudent = false,
}) => ImportedClass(
  sourceSheetName: sheetName,
  scheduleCode: sheetName.substring(0, 2),
  subjectCode: subjectCode,
  classCode: classCode,
  semester: 'FA26',
  students: withStudent
      ? [
          ImportedStudent(
            classCode: classCode,
            rollNumber: 'SE123456',
            fullName: 'Student',
            email: 'student@fpt.edu.vn',
            memberCode: 'Student',
          ),
        ]
      : const [],
  issues: const [],
);
