import 'package:backend/services/qr_service.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'test-secret-key-32-characters-long';

  group('QrService', () {
    test('throws StateError when secret is empty', () {
      expect(
        () => QrService(secret: ''),
        throwsStateError,
      );
    });

    test('creates and successfully verifies a 15-second token', () {
      var fakeTime = DateTime.utc(2026, 9, 16, 10, 0, 0);
      final qrService = QrService(
        secret: secret,
        clock: () => fakeTime,
      );

      final token = qrService.createToken(
        sessionId: 'session-101',
        classId: 'class-SE101',
        windowId: 'win-999',
      );

      expect(token.value, isNotEmpty);
      expect(token.expiresAt.difference(token.issuedAt), const Duration(seconds: 15));

      // Immediate verification
      final claims = qrService.verifyToken(token.value);
      expect(claims, isNotNull);
      expect(claims!.sessionId, 'session-101');
      expect(claims.classId, 'class-SE101');
      expect(claims.windowId, 'win-999');

      // Verify with matching expected ids
      final claimsWithExpected = qrService.verifyToken(
        token.value,
        expectedSessionId: 'session-101',
        expectedClassId: 'class-SE101',
        expectedWindowId: 'win-999',
      );
      expect(claimsWithExpected, isNotNull);
    });

    test('rejects token when expired (> 15 seconds)', () {
      var fakeTime = DateTime.utc(2026, 9, 16, 10, 0, 0);
      final qrService = QrService(
        secret: secret,
        clock: () => fakeTime,
      );

      final token = qrService.createToken(
        sessionId: 'session-101',
        classId: 'class-SE101',
        windowId: 'win-999',
      );

      // Advance clock by 16 seconds
      fakeTime = fakeTime.add(const Duration(seconds: 16));
      final claims = qrService.verifyToken(token.value);
      expect(claims, isNull);
    });

    test('rejects token when tampered or corrupted signature', () {
      final qrService = QrService(secret: secret);
      final token = qrService.createToken(
        sessionId: 'session-101',
        classId: 'class-SE101',
        windowId: 'win-999',
      );

      final tampered = '${token.value}corrupted';
      expect(qrService.verifyToken(tampered), isNull);
    });

    test('rejects token verified by different secret', () {
      final serviceA = QrService(secret: secret);
      final serviceB = QrService(secret: 'different-secret-key-for-test');

      final token = serviceA.createToken(
        sessionId: 'session-101',
        classId: 'class-SE101',
        windowId: 'win-999',
      );

      expect(serviceB.verifyToken(token.value), isNull);
    });

    test('rejects token when expected sessionId or classId do not match', () {
      final qrService = QrService(secret: secret);
      final token = qrService.createToken(
        sessionId: 'session-101',
        classId: 'class-SE101',
        windowId: 'win-999',
      );

      expect(
        qrService.verifyToken(token.value, expectedSessionId: 'wrong-session'),
        isNull,
      );
      expect(
        qrService.verifyToken(token.value, expectedClassId: 'wrong-class'),
        isNull,
      );
      expect(
        qrService.verifyToken(token.value, expectedWindowId: 'wrong-window'),
        isNull,
      );
    });
  });
}
