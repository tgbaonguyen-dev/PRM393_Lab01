import '../models/schedule_models.dart';
import 'schedule_code_parser.dart';

class ScheduleGenerator {
  static const lessonCount = 20;

  static bool isValidFirstDate(String scheduleCode, DateTime firstDate) {
    final rule = ScheduleCodeParser.tryParse(scheduleCode);
    return rule != null && rule.weekdays.contains(firstDate.weekday);
  }

  static List<ClassLesson> generate({
    required String classOfferingId,
    required String scheduleCode,
    required DateTime firstDate,
  }) {
    final rule = ScheduleCodeParser.parse(scheduleCode);
    final normalizedFirstDate = DateTime(
      firstDate.year,
      firstDate.month,
      firstDate.day,
    );
    if (!rule.weekdays.contains(normalizedFirstDate.weekday)) {
      throw ArgumentError(
        'Ngày bắt đầu phải thuộc đúng cặp thứ của mã lịch $scheduleCode.',
      );
    }

    final lessons = <ClassLesson>[];
    var cursor = normalizedFirstDate;
    while (lessons.length < lessonCount) {
      if (rule.weekdays.contains(cursor.weekday)) {
        final sequence = lessons.length + 1;
        lessons.add(
          ClassLesson(
            lessonId:
                '$classOfferingId-L${sequence.toString().padLeft(2, '0')}',
            sequenceNumber: sequence,
            date: cursor,
            dailySlot: rule.dailySlot,
            startTime: rule.startTime,
            endTime: rule.endTime,
          ),
        );
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return lessons;
  }

  static List<ClassLesson> replaceLessonDate({
    required List<ClassLesson> lessons,
    required int sequenceNumber,
    required DateTime newDate,
  }) {
    final normalizedDate = DateTime(newDate.year, newDate.month, newDate.day);
    if (lessons.any(
      (lesson) =>
          lesson.sequenceNumber != sequenceNumber &&
          _sameDate(lesson.date, normalizedDate),
    )) {
      throw ArgumentError('Ngày đã được sử dụng cho một buổi học khác.');
    }

    final index = lessons.indexWhere(
      (lesson) => lesson.sequenceNumber == sequenceNumber,
    );
    if (index < 0) throw ArgumentError('Không tìm thấy buổi học cần chỉnh.');
    if (index > 0 && !normalizedDate.isAfter(lessons[index - 1].date)) {
      throw ArgumentError('Ngày mới phải sau buổi ${sequenceNumber - 1}.');
    }
    if (index < lessons.length - 1 &&
        !normalizedDate.isBefore(lessons[index + 1].date)) {
      throw ArgumentError('Ngày mới phải trước buổi ${sequenceNumber + 1}.');
    }

    final updated = List<ClassLesson>.of(lessons);
    updated[index] = updated[index].copyWith(
      date: normalizedDate,
      isAdjusted: true,
    );
    return updated;
  }

  static bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
