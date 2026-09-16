import '../models/import_models.dart';

/// Combines consecutive Markbook selections without dropping classes that
/// were imported earlier in the same session.
WorkbookImportResult mergeMarkbookImports(
  WorkbookImportResult? current,
  WorkbookImportResult incoming,
) {
  if (current == null) return incoming;

  final merged = List<ImportedClass>.of(current.classes);
  final positions = <String, int>{};
  for (var index = 0; index < merged.length; index++) {
    positions[_classIdentity(merged[index])] = index;
  }

  for (final importedClass in incoming.classes) {
    final identity = _classIdentity(importedClass);
    final existingIndex = positions[identity];
    if (existingIndex == null) {
      positions[identity] = merged.length;
      merged.add(importedClass);
    } else {
      // Re-importing the same offering refreshes its roster and parsed data
      // instead of producing two indistinguishable copies.
      merged[existingIndex] = importedClass;
    }
  }

  return WorkbookImportResult(
    sourceFileName: '${current.sourceFileName}, ${incoming.sourceFileName}',
    classes: merged,
  );
}

String _classIdentity(ImportedClass importedClass) {
  final subject = importedClass.subjectCode.trim().toUpperCase();
  final classCode = importedClass.classCode.trim().toUpperCase();
  if (subject.isNotEmpty || classCode.isNotEmpty) {
    return '$subject|$classCode';
  }

  final students =
      importedClass.students
          .map((student) => student.normalizedRollNumber)
          .where((rollNumber) => rollNumber.isNotEmpty)
          .toList()
        ..sort();
  return '${importedClass.sourceSheetName.trim().toUpperCase()}|${students.join(',')}';
}
