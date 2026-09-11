import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_generator.dart';

void main() {
  test('ScheduleGenerator generates correct sequence and times for schedule 12', () {
    // Schedule 12: Mon & Thu, slot 2 (09:30-11:45)
    // 2026-09-07 is a Monday
    final firstDate = DateTime(2026, 9, 7);
    final lessons = ScheduleGenerator.generateLessons(
      scheduleCode: '12',
      firstDate: firstDate,
      slotCount: 20,
    );

    expect(lessons.length, equals(20));
    expect(lessons.first.date, equals(firstDate));
    expect(lessons.first.startTime, equals('09:30'));
    expect(lessons.first.endTime, equals('11:45'));

    // Second lesson must be Thursday: 2026-09-10
    expect(lessons[1].date, equals(DateTime(2026, 9, 10)));
    // Third lesson must be next Monday: 2026-09-14
    expect(lessons[2].date, equals(DateTime(2026, 9, 14)));
  });

  test('ScheduleGenerator supports dynamic slot counts', () {
    final firstDate = DateTime(2026, 9, 7);
    final lessons = ScheduleGenerator.generateLessons(
      scheduleCode: '12',
      firstDate: firstDate,
      slotCount: 15,
    );
    expect(lessons.length, equals(15));
  });

  test('ScheduleGenerator throws when starting date does not match schedule weekdays', () {
    // 2026-09-06 is a Sunday
    final invalidDate = DateTime(2026, 9, 6);
    expect(
      () => ScheduleGenerator.generateLessons(
        scheduleCode: '12',
        firstDate: invalidDate,
      ),
      throwsArgumentError,
    );
  });
}
