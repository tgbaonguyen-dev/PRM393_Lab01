import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/import/models/import_models.dart';
import 'package:prm393_desktop/features/export/export_dialog.dart';
import 'package:prm393_desktop/shell/app_shell.dart';
import 'support/memory_attendance.dart';

List<ImportedClass> fixtureClasses() => List.generate(8, (i) => ImportedClass(
  sourceSheetName: '${[11,12,14,22,23,24,33,13][i]}_PRM${390+i}_SE${1917+i}',
  scheduleCode: '${[11,12,14,22,23,24,33,13][i]}', subjectCode: 'PRM${390+i}',
  classCode: 'SE${1917+i}', semester: 'FA26', lessonCount: i == 0 ? 22 : 20,
  students: List.generate(35, (j) => ImportedStudent(classCode: 'SE${1917+i}',
    rollNumber: 'SE${190000+j}', fullName: 'Nguyễn Minh ${['Anh','Châu','Hà','Linh','Quân'][j%5]}',
    email: 'student$j@example.com', memberCode: 'Student$j')), issues: const []));

void main() {
  for (final size in [const Size(1920,1080), const Size(1366,768), const Size(1024,600), const Size(800,600)]) {
    testWidgets('all desktop tabs fit ${size.width} x ${size.height}', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final classes = fixtureClasses();
      final nav = AppNavigationController.instance;
      nav.clearWorkspace();
      nav.openScheduleWithClasses(classes: classes, semesterStart: DateTime(2026,9,7));
      final store = MemoryAttendance();
      store.data = {for (final c in classes) c.sourceSheetName: {
        1: {for (var i=0;i<35;i++) 'student$i@example.com': i < 30 ? 'P' : 'A'},
      }};
      final boundaryKey = GlobalKey();
      // Load a real native font for optional visual-review captures.
      final captureDir = Platform.environment['IPRESENT_CAPTURE_DIR'];
      if (captureDir != null) {
        await tester.runAsync(() async {
          final loader = FontLoader('ReviewFont');
          loader.addFont(File('C:/Windows/Fonts/segoeui.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
          await loader.load();
        });
      }
      await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: captureDir == null ? null : 'ReviewFont',
          scaffoldBackgroundColor: const Color(0xFFFAF9F6),
          colorScheme: const ColorScheme.light(primary: Color(0xFF37352F)),
          dividerColor: const Color(0xFFE3E2DE)),
        home: AppShell(loadExistingData: false, storageService: store),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Changing a selected card must not change the calendar row's height.
      final card = find.text('PRM391').first;
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final tab in [0,2,3]) {
        nav.navigateToTab(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'tab $tab at $size');
        if (captureDir != null && size.width == 1366) {
          await tester.runAsync(() async {
            final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$captureDir/tab-$tab.png').writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      expect(store.refreshCount, greaterThan(0));
      expect(find.text('v3.4'), findsNothing);
      nav.openQrForSession(sessionId: 'lesson-01', classId: classes.first.offeringId,
        className: 'PRM390 - SE1917', lessonLabel: 'Buổi 1/22',
        roster: classes.first.students.map((s) => s.toJson()).toList());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'QR at $size');
      expect(find.text('Thiết Lập Thời Gian'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      nav.clearWorkspace();
    });
  }

  testWidgets('export dialog adapts to a short desktop window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800,500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<void>(context: context,
        builder: (_) => ExportDialog(subjectCode: 'PRM393', className: 'SE1917',
          roster: const [], lessonDates: {for(var i=1;i<=60;i++) i:'2026-09-07'},
          attendanceData: const {})), child: const Text('Open'))))));
    await tester.tap(find.text('Open')); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Lưu File'), findsOneWidget);
  });
}
