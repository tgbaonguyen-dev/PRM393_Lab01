/// Attendance status for a student: blank (before first open), absent (A), or present (P)
enum AttendanceStatus {
  blank,
  absent,  // 'A'
  present, // 'P'
}

/// A student's live attendance entry
class LiveStudentAttendance {
  final String studentEmail;
  final String studentName;
  final String rollNumber;
  final AttendanceStatus status;
  final bool isManualOverride;
  final DateTime? checkedInAt;

  const LiveStudentAttendance({
    required this.studentEmail,
    required this.studentName,
    required this.rollNumber,
    required this.status,
    this.isManualOverride = false,
    this.checkedInAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'studentEmail': studentEmail,
      'studentName': studentName,
      'rollNumber': rollNumber,
      'status': status.name,
      'isManualOverride': isManualOverride,
      'checkedInAt': checkedInAt?.toIso8601String(),
    };
  }

  factory LiveStudentAttendance.fromMap(Map<String, dynamic> map) {
    return LiveStudentAttendance(
      studentEmail: map['studentEmail'] as String? ?? '',
      studentName: map['studentName'] as String? ?? '',
      rollNumber: map['rollNumber'] as String? ?? '',
      status: AttendanceStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => AttendanceStatus.blank,
      ),
      isManualOverride: map['isManualOverride'] as bool? ?? false,
      checkedInAt: map['checkedInAt'] != null ? DateTime.tryParse(map['checkedInAt'] as String) : null,
    );
  }
}

/// State of an active attendance window
class AttendanceWindowState {
  final String windowId;
  final String lessonId;
  final bool isOpen;
  final String currentQrToken;
  final DateTime tokenExpiresAt;
  final List<LiveStudentAttendance> rosterResults;

  const AttendanceWindowState({
    required this.windowId,
    required this.lessonId,
    required this.isOpen,
    required this.currentQrToken,
    required this.tokenExpiresAt,
    required this.rosterResults,
  });
}
