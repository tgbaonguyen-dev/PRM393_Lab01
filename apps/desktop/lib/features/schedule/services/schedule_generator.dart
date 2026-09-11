import '../models/lesson_schedule.dart';
import '../../../core/constants/app_constants.dart';

class ScheduleGenerator {
  /// Validates if the selected first date matches the schedule code weekday pair
  static bool isValidFirstDate(String scheduleCode, DateTime firstDate) {
    final validWeekdays = getWeekdaysForScheduleCode(scheduleCode);
    return validWeekdays.contains(firstDate.weekday);
  }

  /// Returns DateTime.weekday numbers for a given schedule code (e.g. 1 -> Mon/Thu)
  static List<int> getWeekdaysForScheduleCode(String scheduleCode) {
    if (scheduleCode.isEmpty) return [DateTime.monday, DateTime.thursday];
    final prefix = scheduleCode[0];

    switch (prefix) {
      case '1':
        return [DateTime.monday, DateTime.thursday]; // Mon (1) & Thu (4)
      case '2':
        return [DateTime.tuesday, DateTime.friday];  // Tue (2) & Fri (5)
      case '3':
        return [DateTime.wednesday, DateTime.saturday]; // Wed (3) & Sat (6)
      default:
        return [DateTime.monday, DateTime.thursday];
    }
  }

  /// Extracts daily slot number (1-4) from schedule code
  static int getDailySlot(String scheduleCode) {
    if (scheduleCode.length < 2) return 1;
    final slot = int.tryParse(scheduleCode[1]) ?? 1;
    return (slot >= 1 && slot <= 4) ? slot : 1;
  }

  /// Generates N chronological lesson dates starting from firstDate
  static List<LessonSchedule> generateLessons({
    required String scheduleCode,
    required DateTime firstDate,
    int slotCount = 20,
  }) {
    final validWeekdays = getWeekdaysForScheduleCode(scheduleCode);
    if (!validWeekdays.contains(firstDate.weekday)) {
      throw ArgumentError(
        'Ngày bắt đầu (${firstDate.toIso8601String().split('T')[0]}) không nằm trong cặp ngày của mã lịch $scheduleCode.',
      );
    }

    final dailySlot = getDailySlot(scheduleCode);
    final times = AppConstants.dailySlots[dailySlot] ?? ('07:00', '09:15');

    final lessons = <LessonSchedule>[];
    var currentDate = DateTime(firstDate.year, firstDate.month, firstDate.day);
    var count = 0;

    while (count < slotCount) {
      if (validWeekdays.contains(currentDate.weekday)) {
        count++;
        lessons.add(LessonSchedule(
          sequenceNumber: count,
          date: currentDate,
          dailySlot: dailySlot,
          startTime: times.$1,
          endTime: times.$2,
          isAdjusted: false,
        ));
      }
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return lessons;
  }
}
