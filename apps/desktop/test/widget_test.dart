import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/main.dart';

void main() {
  testWidgets('LecturerAttendanceApp smoke test', (WidgetTester tester) async {
    // Set standard desktop viewport size
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const LecturerAttendanceApp());
    expect(find.text('PRM393'), findsOneWidget);
    expect(find.text('Nhập Bảng điểm'), findsOneWidget);
  });
}
