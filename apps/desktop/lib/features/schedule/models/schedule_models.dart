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

  ClassLesson copyWith({DateTime? date, bool? isAdjusted}) => ClassLesson(
        lessonId: lessonId,
        sequenceNumber: sequenceNumber,
        date: date ?? this.date,
        dailySlot: dailySlot,
        startTime: startTime,
        endTime: endTime,
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

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
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
