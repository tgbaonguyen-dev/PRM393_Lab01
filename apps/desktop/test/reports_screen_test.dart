import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/reports/reports_screen.dart';
import 'package:prm393_desktop/shell/app_shell.dart';

void main() {
  setUp(() {
    AppNavigationController.instance.activeClasses = [
      ImportedClass(
        sourceSheetName: 'SE1920',
        scheduleCode: '14',
        subjectCode: 'PRM393',
        classCode: 'SE1920',
        semester: 'FA26',
        lessonCount: 20,
        students: [
          const ImportedStudent(
            classCode: 'SE1920',
            rollNumber: 'SE170001',
            fullName: 'Nguyen Van A',
            email: 'anvse170001@fpt.edu.vn',
            memberCode: 'ANV1',
          ),
          const ImportedStudent(
            classCode: 'SE1920',
            rollNumber: 'SE170002',
            fullName: 'Tran Thi B',
            email: 'bttse170002@fpt.edu.vn',
            memberCode: 'BTT2',
          ),
        ],
        issues: const [],
      ),
    ];
  });

  tearDown(() {
    AppNavigationController.instance.activeClasses = null;
  });

  testWidgets('ReportsScreen renders header, summary metrics and student table', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: ReportsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Kiểm tra tiêu đề và các nút
    expect(find.text('Báo Cáo & Thống Kê Điểm Danh'), findsOneWidget);
    expect(find.text('Đồng bộ Google Sheet'), findsOneWidget);
    expect(find.textContaining('Xuất Báo Cáo'), findsOneWidget);

    // 2. Kiểm tra bộ chọn lớp và format
    expect(find.textContaining('PRM393 — SE1920'), findsOneWidget);
    expect(find.text('Excel (.xlsx)'), findsOneWidget);
    expect(find.text('CSV (.csv)'), findsOneWidget);

    // 3. Kiểm tra các metric cards
    expect(find.text('SĨ SỐ LỚP'), findsOneWidget);
    expect(find.text('2 SV'), findsOneWidget);
    expect(find.text('SLOT ĐÃ CHỌN'), findsOneWidget);
    expect(find.text('20 buổi'), findsOneWidget);

    // 4. Kiểm tra bảng sinh viên
    expect(find.text('Nguyen Van A'), findsOneWidget);
    expect(find.text('Tran Thi B'), findsOneWidget);
    expect(find.text('SE170001'), findsOneWidget);
    expect(find.text('SE170002'), findsOneWidget);

    // 5. Kiểm tra tìm kiếm sinh viên
    await tester.enterText(find.widgetWithText(TextField, 'Tìm kiếm MSSV, tên, email...'), 'Nguyen');
    await tester.pumpAndSettle();

    expect(find.text('Nguyen Van A'), findsOneWidget);
    expect(find.text('Tran Thi B'), findsNothing);
  });
}
