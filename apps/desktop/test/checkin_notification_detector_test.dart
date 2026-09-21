import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/session/services/checkin_notification_detector.dart';
import 'package:prm393_desktop/features/session/widgets/checkin_notification_toast.dart';

void main() {
  group('CheckinNotificationDetector', () {
    late CheckinNotificationDetector detector;

    setUp(() {
      detector = CheckinNotificationDetector();
    });

    final testRoster = [
      {
        'rollNumber': 'SE183271',
        'fullName': 'Nguyen Tran Gia Bao',
        'studentEmail': 'baontgse183271@fpt.edu.vn',
      },
      {
        'rollNumber': 'SE183201',
        'fullName': 'Nguyen Phuc Xuan Son',
        'studentEmail': 'sonnpxse183201@fpt.edu.vn',
      },
    ];

    test('first status poll initializes baseline without producing notifications', () {
      final initial = {
        'baontgse183271@fpt.edu.vn': 'P',
        'sonnpxse183201@fpt.edu.vn': 'A',
      };

      final notifications = detector.processNewStatuses(
        newStatuses: initial,
        roster: testRoster,
      );

      expect(notifications, isEmpty);
      expect(detector.isInitialized, isTrue);
    });

    test('detects when an absent student transitions to present P', () {
      detector.initialize({
        'baontgse183271@fpt.edu.vn': 'A',
        'sonnpxse183201@fpt.edu.vn': 'A',
      });

      final fixedTime = DateTime(2026, 9, 20, 10, 30, 0);
      final notifications = detector.processNewStatuses(
        newStatuses: {
          'baontgse183271@fpt.edu.vn': 'P',
          'sonnpxse183201@fpt.edu.vn': 'A',
        },
        roster: testRoster,
        now: fixedTime,
      );

      expect(notifications.length, 1);
      final item = notifications.first;
      expect(item.fullName, 'Nguyen Tran Gia Bao');
      expect(item.rollNumber, 'SE183271');
      expect(item.email, 'baontgse183271@fpt.edu.vn');
      expect(item.timestamp, fixedTime);
    });

    test('does not re-notify when student remains P', () {
      detector.initialize({
        'baontgse183271@fpt.edu.vn': 'P',
      });

      final notifications = detector.processNewStatuses(
        newStatuses: {
          'baontgse183271@fpt.edu.vn': 'P',
        },
        roster: testRoster,
      );

      expect(notifications, isEmpty);
    });

    test('detects multiple check-ins in the same polling cycle', () {
      detector.initialize({
        'baontgse183271@fpt.edu.vn': 'A',
        'sonnpxse183201@fpt.edu.vn': 'A',
      });

      final notifications = detector.processNewStatuses(
        newStatuses: {
          'baontgse183271@fpt.edu.vn': 'P',
          'sonnpxse183201@fpt.edu.vn': 'P',
        },
        roster: testRoster,
      );

      expect(notifications.length, 2);
      expect(notifications.map((n) => n.email), containsAll([
        'baontgse183271@fpt.edu.vn',
        'sonnpxse183201@fpt.edu.vn',
      ]));
    });

    test('manual updateStatus suppresses check-in notification for lecturer manual edit', () {
      detector.initialize({
        'baontgse183271@fpt.edu.vn': 'A',
      });

      // Giảng viên đổi thủ công sang P
      detector.updateStatus('baontgse183271@fpt.edu.vn', 'P');

      // Vòng polling kế tiếp nhận P từ server
      final notifications = detector.processNewStatuses(
        newStatuses: {
          'baontgse183271@fpt.edu.vn': 'P',
        },
        roster: testRoster,
      );

      // Không được kích hoạt toast vì đã được ghi nhận trước đó
      expect(notifications, isEmpty);
    });
  });

  group('CheckinNotificationToast Widget', () {
    testWidgets('renders student info, timestamp, badge and responds to close tap', (tester) async {
      bool dismissed = false;
      final item = CheckinNotificationItem(
        id: 'toast-1',
        fullName: 'Nguyen Tran Gia Bao',
        rollNumber: 'SE183271',
        email: 'baontgse183271@fpt.edu.vn',
        timestamp: DateTime(2026, 9, 20, 14, 25, 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckinNotificationToast(
              item: item,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      expect(find.text('Nguyen Tran Gia Bao'), findsOneWidget);
      expect(find.text('SE183271'), findsOneWidget);
      expect(find.text('Điểm danh thành công'), findsOneWidget);
      expect(find.text('P'), findsOneWidget);
      expect(find.textContaining('14:25:30'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });
}
