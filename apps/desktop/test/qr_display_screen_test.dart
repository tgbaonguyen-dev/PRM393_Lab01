import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prm393_desktop/features/session/qr_display_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('renders initial idle state with open session button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: QrDisplayScreen(
          classId: 'class-123',
          sessionId: 'lesson-01',
          className: 'PRM393 - SE1917',
          lessonLabel: 'Buổi 01/20',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trình chiếu QR điểm danh'), findsOneWidget);
    expect(find.text('PRM393 - SE1917'), findsOneWidget);
    expect(find.text('Buổi 01/20'), findsOneWidget);
    expect(find.text('Mở phiên điểm danh'), findsOneWidget);
    expect(
      find.text('Mở phiên để khởi tạo điểm A và bắt đầu trình chiếu QR.'),
      findsOneWidget,
    );
  });

  testWidgets('opens session and displays rotating QR code and close button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/session/open')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Đã mở phiên điểm danh.',
            'data': {
              'windowId': 'win-test-01',
              'sessionId': 'lesson-01',
              'classId': 'class-123',
              'status': 'open',
              'openedAt': DateTime.now().toUtc().toIso8601String(),
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('/session/qr')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'qrToken': 'token-abc',
              'expiresAt':
                  DateTime.now().toUtc().add(const Duration(seconds: 15)).millisecondsSinceEpoch,
              'qrUrl': 'http://localhost:3000/checkin?token=token-abc',
              'windowId': 'win-test-01',
              'sessionId': 'lesson-01',
              'classId': 'class-123',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('/session/close')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Đã đóng phiên điểm danh.',
            'data': {
              'windowId': 'win-test-01',
              'sessionId': 'lesson-01',
              'classId': 'class-123',
              'status': 'closed',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('Not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: QrDisplayScreen(
          classId: 'class-123',
          sessionId: 'lesson-01',
          className: 'PRM393 - SE1917',
          lessonLabel: 'Buổi 01/20',
          client: mockClient,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap open session
    await tester.tap(find.text('Mở phiên điểm danh'));
    await tester.pumpAndSettle();

    // Verify QR code is rendered and close session button is visible
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Đóng phiên'), findsOneWidget);
    expect(find.text('Sao chép link'), findsOneWidget);

    // Tap copy link button
    await tester.tap(find.text('Sao chép link'));
    await tester.pumpAndSettle();
    expect(find.text('Đã sao chép link điểm danh vào bộ nhớ tạm!'), findsOneWidget);

    // Tap close session
    await tester.tap(find.text('Đóng phiên'));
    await tester.pumpAndSettle();

    // Session is now closed
    expect(find.text('Mở lại phiên'), findsOneWidget);
    expect(
      find.text('Phiên đã đóng. Kết quả hiện tại được giữ nguyên.'),
      findsOneWidget,
    );
  });
}
