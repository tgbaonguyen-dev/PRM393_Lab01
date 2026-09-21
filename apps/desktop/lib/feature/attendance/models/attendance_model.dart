// Model đại diện cho một bản ghi điểm danh của 1 sinh viên
class StudentAttendanceRecord {
  final String rollNumber;
  final String fullName;
  final String email;
  final String status; // "P", "A", hoặc "" (trống)
  final bool isManualEdited;

  StudentAttendanceRecord({
    required this.rollNumber,
    required this.fullName,
    required this.email,
    required this.status,
    this.isManualEdited = false,
  });

  factory StudentAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return StudentAttendanceRecord(
      rollNumber: json['rollNumber'] ?? json['RollNumber'] ?? '',
      fullName: json['fullName'] ?? json['FullName'] ?? '',
      email:
          json['studentEmail'] ??
          json['StudentEmail'] ??
          json['email'] ??
          json['Email'] ??
          '',
      status: (json['status'] ?? json['Status'] ?? '').toString().toUpperCase(),
      isManualEdited:
          json['isManualEdited'] == true || json['is_manual_edited'] == true,
    );
  }

  /// Trạng thái có mặt
  bool get isPresent => status == 'P';

  /// Trạng thái vắng mặt
  bool get isAbsent => status == 'A';

  /// Chưa có kết quả
  bool get isUnmarked => status.isEmpty;
}

/// Model thống kê sĩ số lớp học (Live Counters)
class AttendanceSummary {
  final int total;
  final int present;
  final int absent;
  AttendanceSummary({
    required this.total,
    required this.present,
    required this.absent,
  });
  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      total: json['total'] ?? 0,
      present: json['present'] ?? 0,
      absent: json['absent'] ?? 0,
    );
  }

  /// Tỷ lệ có mặt (%)
  double get attendanceRate => total > 0 ? (present / total) * 100 : 0.0;
}
