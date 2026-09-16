import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/schedule/schedule_generator_screen.dart';

void main() {
  testWidgets('shows all imported classes in the weekly timetable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleGeneratorScreen(
          importedClasses: [
            _class('12_PRM393_SE1917', '12', 'PRM393', 'SE1917', 20),
            _class('23_PRN232_SE1920', '23', 'PRN232', 'SE1920', 12),
          ],
          semesterStart: DateTime(2026, 9, 7),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 lớp • 32 buổi'), findsOneWidget);
    expect(find.text('PRM393'), findsWidgets);
    expect(find.text('PRN232'), findsWidgets);
    expect(find.text('Buổi 01 / 20'), findsOneWidget);
    expect(find.text('Buổi 01 / 12'), findsOneWidget);
    expect(find.text('Mở điểm danh • Chờ M2'), findsOneWidget);
    expect(find.text('Đổi lịch buổi đã chọn'), findsOneWidget);
    expect(find.text('Xác nhận buổi'), findsNothing);
    expect(find.text('Lưu lịch học'), findsOneWidget);
  });

  testWidgets('shows only slots used by the imported class schedules', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleGeneratorScreen(
          importedClasses: [
            _class('11_PRM111_SE1917', '11', 'PRM111', 'SE1917', 20),
            _class('14_PRM114_SE1918', '14', 'PRM114', 'SE1918', 20),
            _class('15_PRM115_SE1919', '15', 'PRM115', 'SE1919', 20),
          ],
          semesterStart: DateTime(2026, 9, 7),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.text('Slot 4'), findsOneWidget);
    expect(find.text('Slot 5'), findsOneWidget);
    expect(find.text('Slot 2'), findsNothing);
    expect(find.text('Slot 6'), findsNothing);
    expect(find.text('Slot 7'), findsNothing);
  });

  testWidgets('lesson adjustment dialog shows both date and slot controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleGeneratorScreen(
          importedClasses: [
            _class('12_PRM393_SE1917', '12', 'PRM393', 'SE1917', 20),
          ],
          semesterStart: DateTime(2026, 9, 7),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buổi 01 / 20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi lịch buổi đã chọn'));
    await tester.pumpAndSettle();

    expect(find.text('Điều chỉnh buổi học'), findsOneWidget);
    expect(find.text('Ngày học'), findsOneWidget);
    expect(find.text('Slot mới'), findsOneWidget);
    expect(find.text('Đổi ngày'), findsOneWidget);
    expect(find.text('Áp dụng'), findsOneWidget);
  });
}

ImportedClass _class(
  String sheetName,
  String scheduleCode,
  String subjectCode,
  String classCode,
  int lessonCount,
) => ImportedClass(
  sourceSheetName: sheetName,
  scheduleCode: scheduleCode,
  subjectCode: subjectCode,
  classCode: classCode,
  semester: 'FA26',
  students: const [],
  issues: const [],
  lessonCount: lessonCount,
);
