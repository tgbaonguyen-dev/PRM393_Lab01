import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/schedule/models/schedule_models.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_code_parser.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_generator.dart';

void main() {
  test('restores a Google Sheets date string returned by Apps Script', () {
    final lesson = ClassLesson.fromJson({
      'lessonId': 'lesson-1',
      'sequenceNumber': 1,
      'date': 'Mon Sep 07 2026 00:00:00 GMT+0700 (Giờ Đông Dương)',
      'dailySlot': 1,
      'startTime': 'Sat Dec 30 1899 07:14:42 GMT+0706 (Giờ Đông Dương)',
      'endTime': 'Sat Dec 30 1899 09:29:42 GMT+0706 (Giờ Đông Dương)',
    });

    expect(lesson.date, DateTime(2026, 9, 7));
    expect(lesson.startTime, '07:00');
    expect(lesson.endTime, '09:15');
  });

  test('parses schedule code 12', () {
    final rule = ScheduleCodeParser.parse('12');

    expect(rule.weekdays, [DateTime.monday, DateTime.thursday]);
    expect(rule.dailySlot, 2);
    expect(rule.startTime, '09:30');
    expect(rule.endTime, '11:45');
  });

  test('maps 1X, 2X and 3X to the correct weekday pair and slot X', () {
    final group1 = ScheduleCodeParser.parse('14');
    final group2 = ScheduleCodeParser.parse('23');
    final group3 = ScheduleCodeParser.parse('31');

    expect(group1.weekdays, [DateTime.monday, DateTime.thursday]);
    expect(group1.dailySlot, 4);
    expect(group2.weekdays, [DateTime.tuesday, DateTime.friday]);
    expect(group2.dailySlot, 3);
    expect(group3.weekdays, [DateTime.wednesday, DateTime.saturday]);
    expect(group3.dailySlot, 1);
  });

  test('supports the final evening slot 5', () {
    final slot5 = ScheduleCodeParser.parse('15');

    expect(slot5.startTime, '17:45');
    expect(slot5.endTime, '19:15');
    expect(() => ScheduleCodeParser.parse('16'), throwsFormatException);
  });

  test('rejects an invalid schedule code', () {
    expect(() => ScheduleCodeParser.parse('9X'), throwsFormatException);
  });

  test('generates exactly 20 chronological lessons', () {
    final lessons = ScheduleGenerator.generate(
      classOfferingId: 'PRM393_SE1917_FA26',
      scheduleCode: '12',
      firstDate: DateTime(2026, 9, 7),
    );

    expect(lessons, hasLength(20));
    expect(lessons.first.date, DateTime(2026, 9, 7));
    expect(lessons[1].date, DateTime(2026, 9, 10));
    expect(lessons[2].date, DateTime(2026, 9, 14));
    expect(lessons.last.sequenceNumber, 20);
    expect(lessons.every((lesson) => lesson.dailySlot == 2), isTrue);
  });

  test('generates custom 12 and 15 lesson schedules', () {
    for (final lessonCount in [12, 15]) {
      final lessons = ScheduleGenerator.generate(
        classOfferingId: 'VOV_SE1917_FA26',
        scheduleCode: '23',
        firstDate: DateTime(2026, 9, 8),
        lessonCount: lessonCount,
      );

      expect(lessons, hasLength(lessonCount));
      expect(lessons.last.sequenceNumber, lessonCount);
      expect(lessons.every((lesson) => lesson.dailySlot == 3), isTrue);
    }
  });

  test('finds the first valid class date from a semester anchor', () {
    final firstDate = ScheduleGenerator.firstTeachingDateOnOrAfter(
      scheduleCode: '31',
      semesterStart: DateTime(2026, 9, 7),
    );

    expect(firstDate, DateTime(2026, 9, 9));
  });

  test('rejects a first date outside the weekday pair', () {
    expect(
      () => ScheduleGenerator.generate(
        classOfferingId: 'PRM393_SE1917_FA26',
        scheduleCode: '12',
        firstDate: DateTime(2026, 9, 8),
      ),
      throwsArgumentError,
    );
  });

  test('adjusts one lesson and rejects duplicate dates', () {
    final lessons = ScheduleGenerator.generate(
      classOfferingId: 'PRM393_SE1917_FA26',
      scheduleCode: '12',
      firstDate: DateTime(2026, 9, 7),
    );
    final adjusted = ScheduleGenerator.replaceLessonDate(
      lessons: lessons,
      sequenceNumber: 2,
      newDate: DateTime(2026, 9, 11),
    );

    expect(adjusted[1].date, DateTime(2026, 9, 11));
    expect(adjusted[1].isAdjusted, isTrue);
    final movedToEvening = ScheduleGenerator.replaceLessonDate(
      lessons: lessons,
      sequenceNumber: 1,
      newDate: DateTime(2026, 9, 7),
      newDailySlot: 5,
    );
    expect(movedToEvening.first.dailySlot, 5);
    expect(movedToEvening.first.startTime, '17:45');
    expect(movedToEvening.first.endTime, '19:15');
    expect(
      () => ScheduleGenerator.replaceLessonDate(
        lessons: lessons,
        sequenceNumber: 2,
        newDate: lessons.first.date,
      ),
      throwsArgumentError,
    );
  });
}
