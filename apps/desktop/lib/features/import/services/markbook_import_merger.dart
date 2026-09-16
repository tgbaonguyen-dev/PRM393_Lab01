import '../models/import_models.dart';

/// Appends a newly selected Markbook to the current in-memory import.
/// Duplicate offerings are intentionally retained so the cross-file
/// validator can show both conflicts and require lecturer confirmation.
WorkbookImportResult mergeMarkbookImports(
  WorkbookImportResult? current,
  WorkbookImportResult incoming,
) {
  if (current == null) return incoming;
  return WorkbookImportResult(
    sourceFileName: '${current.sourceFileName}, ${incoming.sourceFileName}',
    classes: [...current.classes, ...incoming.classes],
  );
}
