/// Roster entry imported from markbook (.xlsx or .ods)
class RosterStudent {
  final String rollNumber;
  final String fullName;
  final String email;
  final String? memberCode;
  final String className;

  const RosterStudent({
    required this.rollNumber,
    required this.fullName,
    required this.email,
    this.memberCode,
    required this.className,
  });

  factory RosterStudent.fromMap(Map<String, dynamic> map) {
    return RosterStudent(
      rollNumber: map['rollNumber'] as String? ?? '',
      fullName: map['fullName'] as String? ?? '',
      email: (map['email'] as String? ?? '').trim().toLowerCase(),
      memberCode: map['memberCode'] as String?,
      className: map['className'] as String? ?? '',
    );
  }
}

/// Class offering parsed from markbook worksheet
class ClassOfferingData {
  final String scheduleCode; // e.g. "12"
  final String subjectCode;  // e.g. "PRM393"
  final String className;    // e.g. "SE1917"
  final String semester;
  final List<RosterStudent> roster;

  const ClassOfferingData({
    required this.scheduleCode,
    required this.subjectCode,
    required this.className,
    required this.semester,
    required this.roster,
  });
}
