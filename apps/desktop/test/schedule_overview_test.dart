import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_generator.dart';
import 'package:prm393_desktop/features/schedule/services/schedule_overview.dart';

void main() {
  final mondayClass = _class('12_PRM393_SE1917', '12', 'PRM393', 'SE1917');
  final tuesdayClass = _class('23_PRN232_SE1920', '23', 'PRN232', 'SE1920');
  final classes = [mondayClass, tuesdayClass];
  final schedules = {
    mondayClass.sourceSheetName: ScheduleGenerator.generate(
      classOfferingId: mondayClass.offeringId,
      scheduleCode: mondayClass.scheduleCode,
      firstDate: DateTime(2026, 9, 7),
    ),
    tuesdayClass.sourceSheetName: ScheduleGenerator.generate(
      classOfferingId: tuesdayClass.offeringId,
      scheduleCode: tuesdayClass.scheduleCode,
      firstDate: DateTime(2026, 9, 8),
      lessonCount: 12,
    ),
  };

  test('weekly cells combine lessons from all imported classes', () {
    final monday = ScheduleOverview.lessonsForCell(
      classes: classes,
      schedules: schedules,
      date: DateTime(2026, 9, 7),
      dailySlot: 2,
    );
    final tuesday = ScheduleOverview.lessonsForCell(
      classes: classes,
      schedules: schedules,
      date: DateTime(2026, 9, 8),
      dailySlot: 3,
    );

    expect(monday.single.importedClass.classCode, 'SE1917');
    expect(tuesday.single.importedClass.classCode, 'SE1920');
  });

  test('suggests a lesson only while its actual time is in progress', () {
    final current = ScheduleOverview.findCurrentLesson(
      classes: classes,
      schedules: schedules,
      now: DateTime(2026, 9, 7, 10),
    );
    final outside = ScheduleOverview.findCurrentLesson(
      classes: classes,
      schedules: schedules,
      now: DateTime(2026, 9, 7, 12),
    );

    expect(current?.importedClass.subjectCode, 'PRM393');
    expect(current?.lesson.sequenceNumber, 1);
    expect(outside, isNull);
  });
}

ImportedClass _class(
  String sheetName,
  String scheduleCode,
  String subjectCode,
  String classCode,
) => ImportedClass(
  sourceSheetName: sheetName,
  scheduleCode: scheduleCode,
  subjectCode: subjectCode,
  classCode: classCode,
  semester: 'FA26',
  students: const [],
  issues: const [],
  lessonCount: subjectCode == 'PRN232' ? 12 : 20,
);
