import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_code_parser.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_generator.dart';

void main() {
  test('parses schedule code 12', () {
    final rule = ScheduleCodeParser.parse('12');

    expect(rule.weekdays, [DateTime.monday, DateTime.thursday]);
    expect(rule.dailySlot, 2);
    expect(rule.startTime, '09:30');
    expect(rule.endTime, '11:45');
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
