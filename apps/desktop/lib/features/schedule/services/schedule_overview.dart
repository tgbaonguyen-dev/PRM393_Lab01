import '../../import/models/import_models.dart';
import '../models/schedule_models.dart';

class ScheduledLessonView {
  final ImportedClass importedClass;
  final ClassLesson lesson;

  const ScheduledLessonView({
    required this.importedClass,
    required this.lesson,
  });

  String get key => '${importedClass.sourceSheetName}:${lesson.lessonId}';
}

class ScheduleOverview {
  static DateTime startOfWeek(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static List<ScheduledLessonView> allLessons({
    required List<ImportedClass> classes,
    required Map<String, List<ClassLesson>> schedules,
    String? classFilter,
  }) {
    final result = <ScheduledLessonView>[];
    for (final importedClass in classes) {
      if (classFilter != null && importedClass.sourceSheetName != classFilter) {
        continue;
      }
      for (final lesson
          in schedules[importedClass.sourceSheetName] ?? const []) {
        result.add(
          ScheduledLessonView(importedClass: importedClass, lesson: lesson),
        );
      }
    }
    result.sort((left, right) {
      final byDate = left.lesson.date.compareTo(right.lesson.date);
      if (byDate != 0) return byDate;
      final bySlot = left.lesson.dailySlot.compareTo(right.lesson.dailySlot);
      if (bySlot != 0) return bySlot;
      return left.importedClass.classCode.compareTo(
        right.importedClass.classCode,
      );
    });
    return result;
  }

  static List<ScheduledLessonView> lessonsForCell({
    required List<ImportedClass> classes,
    required Map<String, List<ClassLesson>> schedules,
    required DateTime date,
    required int dailySlot,
    String? classFilter,
  }) =>
      allLessons(
            classes: classes,
            schedules: schedules,
            classFilter: classFilter,
          )
          .where((item) {
            return _sameDay(item.lesson.date, date) &&
                item.lesson.dailySlot == dailySlot;
          })
          .toList(growable: false);

  static ScheduledLessonView? findCurrentLesson({
    required List<ImportedClass> classes,
    required Map<String, List<ClassLesson>> schedules,
    required DateTime now,
  }) {
    for (final item in allLessons(classes: classes, schedules: schedules)) {
      final start = _atTime(item.lesson.date, item.lesson.startTime);
      var end = _atTime(item.lesson.date, item.lesson.endTime);
      if (!end.isAfter(start)) {
        end = end.add(const Duration(days: 1));
      }
      if (!now.isBefore(start) && !now.isAfter(end)) {
        return item;
      }
    }
    return null;
  }

  static ScheduledLessonView? findByKey({
    required String? key,
    required List<ImportedClass> classes,
    required Map<String, List<ClassLesson>> schedules,
  }) {
    if (key == null) return null;
    for (final item in allLessons(classes: classes, schedules: schedules)) {
      if (item.key == key) return item;
    }
    return null;
  }

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static DateTime _atTime(DateTime date, String value) {
    final minutes = _minutes(value);
    return DateTime(
      date.year,
      date.month,
      date.day,
      minutes ~/ 60,
      minutes % 60,
    );
  }
}
