class ScheduleRule {
  final String code;
  final List<int> weekdays;
  final int dailySlot;
  final String startTime;
  final String endTime;

  const ScheduleRule({
    required this.code,
    required this.weekdays,
    required this.dailySlot,
    required this.startTime,
    required this.endTime,
  });
}

class ClassLesson {
  final String lessonId;
  final int sequenceNumber;
  final DateTime date;
  final int dailySlot;
  final String startTime;
  final String endTime;
  final bool isAdjusted;

  const ClassLesson({
    required this.lessonId,
    required this.sequenceNumber,
    required this.date,
    required this.dailySlot,
    required this.startTime,
    required this.endTime,
    this.isAdjusted = false,
  });

  ClassLesson copyWith({
    DateTime? date,
    int? dailySlot,
    String? startTime,
    String? endTime,
    bool? isAdjusted,
  }) => ClassLesson(
    lessonId: lessonId,
    sequenceNumber: sequenceNumber,
    date: date ?? this.date,
    dailySlot: dailySlot ?? this.dailySlot,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    isAdjusted: isAdjusted ?? this.isAdjusted,
  );

  Map<String, dynamic> toJson() => {
    'lessonId': lessonId,
    'sequenceNumber': sequenceNumber,
    'date': _dateOnly(date),
    'dailySlot': dailySlot,
    'startTime': startTime,
    'endTime': endTime,
    'status': 'scheduled',
    'isAdjusted': isAdjusted,
  };

  factory ClassLesson.fromJson(Map<String, dynamic> json) {
    final dailySlot = json['dailySlot'] is num
        ? (json['dailySlot'] as num).toInt()
        : int.tryParse(json['dailySlot']?.toString() ?? '') ?? 0;
    final sequenceNumber = json['sequenceNumber'] is num
        ? (json['sequenceNumber'] as num).toInt()
        : int.tryParse(json['sequenceNumber']?.toString() ?? '') ?? 0;
    return ClassLesson(
      lessonId: json['lessonId']?.toString() ?? '',
      sequenceNumber: sequenceNumber,
      date: _parseDate(json['date']),
      dailySlot: dailySlot,
      startTime: _parseTime(json['startTime'], dailySlot, isStart: true),
      endTime: _parseTime(json['endTime'], dailySlot, isStart: false),
      isAdjusted: json['isAdjusted'] == true,
    );
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Google Sheets may serialize a date as either `2026-09-07` or as
  /// `Mon Sep 07 2026 00:00:00 GMT+0700 (...)`. Accept both formats so a
  /// saved schedule can always be restored after reopening the app.
  static DateTime _parseDate(Object? rawValue) {
    final raw = rawValue?.toString().trim() ?? '';
    final isoDate = DateTime.tryParse(raw);
    if (isoDate != null) return isoDate;

    final match = RegExp(
      r'^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})',
    ).firstMatch(raw);
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = match == null ? null : months[match.group(1)!.toLowerCase()];
    if (match != null && month != null) {
      return DateTime(
        int.parse(match.group(3)!),
        month,
        int.parse(match.group(2)!),
      );
    }
    throw FormatException('Invalid date format: $raw');
  }

  static const _slotTimes = <int, (String, String)>{
    1: ('07:00', '09:15'),
    2: ('09:30', '11:45'),
    3: ('12:30', '14:45'),
    4: ('15:00', '17:15'),
    5: ('17:45', '19:15'),
  };

  static String _parseTime(
    Object? rawValue,
    int dailySlot, {
    required bool isStart,
  }) {
    final slotTime = _slotTimes[dailySlot];
    if (slotTime != null) return isStart ? slotTime.$1 : slotTime.$2;

    final raw = rawValue?.toString().trim() ?? '';
    if (RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(raw)) {
      return raw.padLeft(5, '0');
    }
    return raw;
  }
}

class ClassSchedule {
  final String classOfferingId;
  final String sourceSheetName;
  final String scheduleCode;
  final String subjectCode;
  final String classCode;
  final String semester;
  final List<ClassLesson> lessons;

  const ClassSchedule({
    required this.classOfferingId,
    required this.sourceSheetName,
    required this.scheduleCode,
    required this.subjectCode,
    required this.classCode,
    required this.semester,
    required this.lessons,
  });
}
