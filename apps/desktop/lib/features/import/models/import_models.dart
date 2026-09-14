enum ValidationSeverity { warning, error }

class ImportValidationIssue {
  final ValidationSeverity severity;
  final String code;
  final String message;
  final String sheetName;
  final int? rowNumber;
  final String? field;

  const ImportValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    required this.sheetName,
    this.rowNumber,
    this.field,
  });

  bool get isError => severity == ValidationSeverity.error;
}

class ImportedStudent {
  final String classCode;
  final String rollNumber;
  final String fullName;
  final String email;
  final String memberCode;

  const ImportedStudent({
    required this.classCode,
    required this.rollNumber,
    required this.fullName,
    required this.email,
    required this.memberCode,
  });

  String get normalizedRollNumber => rollNumber.trim().toUpperCase();
  String get normalizedEmail => email.trim().toLowerCase();

  Map<String, dynamic> toJson() => {
    'classCode': classCode,
    'rollNumber': rollNumber,
    'fullName': fullName,
    'email': normalizedEmail,
    'memberCode': memberCode,
  };
}

class ImportedClass {
  final String sourceSheetName;
  final String scheduleCode;
  final String subjectCode;
  final String classCode;
  final String semester;
  final int lessonCount;
  final List<ImportedStudent> students;
  final List<ImportValidationIssue> issues;

  const ImportedClass({
    required this.sourceSheetName,
    required this.scheduleCode,
    required this.subjectCode,
    required this.classCode,
    required this.students,
    required this.issues,
    this.semester = '',
    this.lessonCount = 20,
  });

  bool get hasErrors => issues.any((issue) => issue.isError);
  bool get isReady => !hasErrors && semester.trim().isNotEmpty;

  String get offeringId => [
    subjectCode,
    classCode,
    semester,
  ].map((value) => value.trim().toUpperCase()).join('_');

  ImportedClass copyWith({
    String? scheduleCode,
    String? subjectCode,
    String? classCode,
    String? semester,
    int? lessonCount,
    List<ImportValidationIssue>? issues,
  }) => ImportedClass(
    sourceSheetName: sourceSheetName,
    scheduleCode: scheduleCode ?? this.scheduleCode,
    subjectCode: subjectCode ?? this.subjectCode,
    classCode: classCode ?? this.classCode,
    semester: semester ?? this.semester,
    lessonCount: lessonCount ?? this.lessonCount,
    students: students,
    issues: issues ?? this.issues,
  );
}

class WorkbookImportResult {
  final String sourceFileName;
  final List<ImportedClass> classes;

  const WorkbookImportResult({
    required this.sourceFileName,
    required this.classes,
  });

  int get totalStudents => classes.fold(
    0,
    (total, importedClass) => total + importedClass.students.length,
  );
}
