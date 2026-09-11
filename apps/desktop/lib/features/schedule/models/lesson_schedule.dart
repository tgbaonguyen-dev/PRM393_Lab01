/// Model representing one of the 20 generated lessons for a class offering
class LessonSchedule {
  final int sequenceNumber; // 1 to 20
  final DateTime date;
  final int dailySlot;      // 1 to 4
  final String startTime;   // e.g. "09:30"
  final String endTime;     // e.g. "11:45"
  final bool isAdjusted;    // True if adjusted for holiday/makeup

  const LessonSchedule({
    required this.sequenceNumber,
    required this.date,
    required this.dailySlot,
    required this.startTime,
    required this.endTime,
    this.isAdjusted = false,
  });

  LessonSchedule copyWith({
    DateTime? date,
    int? dailySlot,
    String? startTime,
    String? endTime,
    bool? isAdjusted,
  }) {
    return LessonSchedule(
      sequenceNumber: sequenceNumber,
      date: date ?? this.date,
      dailySlot: dailySlot ?? this.dailySlot,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAdjusted: isAdjusted ?? this.isAdjusted,
    );
  }
}
