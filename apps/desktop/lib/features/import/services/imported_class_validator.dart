import '../models/import_models.dart';

const duplicateOfferingIssueCode = 'duplicate_class_offering';

/// Marks every class whose normalized subject-code/class-code pair appears
/// more than once. The lecturer must resolve these conflicts before schedule
/// generation so two inputs can never overwrite the same persisted offering.
List<ImportedClass> validateDistinctClassOfferings(
  List<ImportedClass> classes,
) {
  final counts = <String, int>{};
  for (final importedClass in classes) {
    final key = _offeringKey(importedClass);
    if (key != null) counts[key] = (counts[key] ?? 0) + 1;
  }

  return classes
      .map((importedClass) {
        final issues = importedClass.issues
            .where((issue) => issue.code != duplicateOfferingIssueCode)
            .toList();
        final key = _offeringKey(importedClass);
        if (key != null && (counts[key] ?? 0) > 1) {
          issues.add(
            ImportValidationIssue(
              severity: ValidationSeverity.error,
              code: duplicateOfferingIssueCode,
              message:
                  'Trùng mã môn ${importedClass.subjectCode.trim().toUpperCase()} '
                  'và mã lớp ${importedClass.classCode.trim().toUpperCase()}. '
                  'Hãy sửa một trong hai mã và xác nhận lại.',
              sheetName: importedClass.sourceSheetName,
              field: 'SubjectCode/ClassCode',
            ),
          );
        }
        return importedClass.copyWith(issues: issues);
      })
      .toList(growable: false);
}

String? _offeringKey(ImportedClass importedClass) {
  final subjectCode = importedClass.subjectCode.trim().toUpperCase();
  final classCode = importedClass.classCode.trim().toUpperCase();
  if (subjectCode.isEmpty || classCode.isEmpty) return null;
  return '$subjectCode|$classCode';
}
