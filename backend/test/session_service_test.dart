import 'package:backend/repositories/sheets_repository.dart';
import 'package:backend/services/session_service.dart';
import 'package:test/test.dart';

class _FakeSheetsRepository extends SheetsRepository {
  Map<String, dynamic>? activeWindowData;
  bool closeResult = true;

  _FakeSheetsRepository() : super(gatewayUrl: 'http://localhost');

  @override
  Future<Map<String, dynamic>?> openAttendanceWindow(String sessionId) async {
    activeWindowData = {
      'windowId': 'win-001',
      'sessionId': sessionId,
      'openedAt': DateTime.now().toUtc().toIso8601String(),
      'isOpen': true,
    };
    return activeWindowData;
  }

  @override
  Future<Map<String, dynamic>?> getActiveWindow(String sessionId) async {
    return activeWindowData;
  }

  @override
  Future<bool> closeAttendanceWindow(String windowId) async {
    if (activeWindowData != null && activeWindowData!['windowId'] == windowId) {
      activeWindowData!['isOpen'] = false;
      activeWindowData!['closedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    return closeResult;
  }
}

void main() {
  group('SessionService', () {
    late _FakeSheetsRepository fakeRepo;
    late SessionService sessionService;

    setUp(() {
      fakeRepo = _FakeSheetsRepository();
      sessionService = SessionService(repository: fakeRepo);
    });

    test('openSession creates and returns open AttendanceWindow', () async {
      final window = await sessionService.openSession(
        sessionId: 'session-123',
        classId: 'class-abc',
      );

      expect(window.windowId, 'win-001');
      expect(window.sessionId, 'session-123');
      expect(window.classId, 'class-abc');
      expect(window.isOpen, isTrue);
    });

    test('openSession rejects empty sessionId or classId', () async {
      expect(
        () => sessionService.openSession(sessionId: '', classId: 'class-abc'),
        throwsA(isA<SessionValidationException>()),
      );
      expect(
        () => sessionService.openSession(sessionId: 'session-123', classId: '   '),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('requireOpenSession succeeds when session is open', () async {
      await sessionService.openSession(
        sessionId: 'session-123',
        classId: 'class-abc',
      );

      final active = await sessionService.requireOpenSession(
        sessionId: 'session-123',
        classId: 'class-abc',
      );
      expect(active.isOpen, isTrue);
    });

    test('requireOpenSession throws SESSION_CLOSED when no open session', () async {
      expect(
        () => sessionService.requireOpenSession(
          sessionId: 'session-nonexistent',
          classId: 'class-abc',
        ),
        throwsA(
          isA<SessionStateException>().having(
            (e) => e.code,
            'code',
            'SESSION_CLOSED',
          ),
        ),
      );
    });

    test('closeSession marks session as closed', () async {
      final opened = await sessionService.openSession(
        sessionId: 'session-123',
        classId: 'class-abc',
      );

      final closed = await sessionService.closeSession(
        sessionId: 'session-123',
        classId: 'class-abc',
        windowId: opened.windowId,
      );

      expect(closed.isOpen, isFalse);
      expect(closed.closedAt, isNotNull);
    });

    test('closeSession throws WINDOW_REPLACED if windowId does not match', () async {
      await sessionService.openSession(
        sessionId: 'session-123',
        classId: 'class-abc',
      );

      expect(
        () => sessionService.closeSession(
          sessionId: 'session-123',
          classId: 'class-abc',
          windowId: 'different-window-id',
        ),
        throwsA(
          isA<SessionStateException>().having(
            (e) => e.code,
            'code',
            'WINDOW_REPLACED',
          ),
        ),
      );
    });
  });
}
