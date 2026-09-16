import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const Duration qrTokenLifetime = Duration(seconds: 15);

typedef QrClock = DateTime Function();

class QrToken {
  final String value;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const QrToken({
    required this.value,
    required this.issuedAt,
    required this.expiresAt,
  });
}

class QrTokenClaims {
  final String sessionId;
  final String classId;
  final String windowId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const QrTokenClaims({
    required this.sessionId,
    required this.classId,
    required this.windowId,
    required this.issuedAt,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'classId': classId,
        'windowId': windowId,
        'issuedAt': issuedAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };
}

/// Creates and verifies short-lived QR tokens using a server-held HMAC key.
class QrService {
  final List<int> _secretBytes;
  final QrClock _clock;
  final Duration tokenLifetime;

  QrService({
    String? secret,
    QrClock? clock,
    this.tokenLifetime = qrTokenLifetime,
  })  : _secretBytes = utf8.encode(
          (secret ?? Platform.environment['QR_HMAC_SECRET'] ?? '').trim(),
        ),
        _clock = clock ?? DateTime.now {
    if (_secretBytes.isEmpty) {
      throw StateError('QR_HMAC_SECRET chưa được cấu hình trên backend.');
    }
    if (tokenLifetime <= Duration.zero || tokenLifetime > qrTokenLifetime) {
      throw ArgumentError.value(
        tokenLifetime,
        'tokenLifetime',
        'Thời hạn QR phải lớn hơn 0 và không vượt quá 15 giây.',
      );
    }
  }

  QrToken createToken({
    required String sessionId,
    required String classId,
    required String windowId,
  }) {
    final normalizedSessionId = _required(sessionId, 'sessionId');
    final normalizedClassId = _required(classId, 'classId');
    final normalizedWindowId = _required(windowId, 'windowId');
    final issuedAt = _clock().toUtc();
    final expiresAt = issuedAt.add(tokenLifetime);
    final claims = QrTokenClaims(
      sessionId: normalizedSessionId,
      classId: normalizedClassId,
      windowId: normalizedWindowId,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );

    final payloadBytes = utf8.encode(jsonEncode(claims.toJson()));
    final signature = Hmac(sha256, _secretBytes).convert(payloadBytes).bytes;
    final value = '${_encode(payloadBytes)}.${_encode(signature)}';
    return QrToken(value: value, issuedAt: issuedAt, expiresAt: expiresAt);
  }

  QrTokenClaims? verifyToken(
    String token, {
    String? expectedSessionId,
    String? expectedClassId,
    String? expectedWindowId,
  }) {
    try {
      final parts = token.trim().split('.');
      if (parts.length != 2) return null;

      final payloadBytes = base64Url.decode(base64Url.normalize(parts[0]));
      final signatureBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final expectedSignature =
          Hmac(sha256, _secretBytes).convert(payloadBytes).bytes;
      if (!_constantTimeEquals(signatureBytes, expectedSignature)) return null;

      final decoded = jsonDecode(utf8.decode(payloadBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final sessionId = decoded['sessionId']?.toString().trim() ?? '';
      final classId = decoded['classId']?.toString().trim() ?? '';
      final windowId = decoded['windowId']?.toString().trim() ?? '';
      final issuedAtMs = int.tryParse(decoded['issuedAt']?.toString() ?? '');
      final expiresAtMs = int.tryParse(decoded['expiresAt']?.toString() ?? '');
      if (sessionId.isEmpty ||
          classId.isEmpty ||
          windowId.isEmpty ||
          issuedAtMs == null ||
          expiresAtMs == null) {
        return null;
      }

      final issuedAt = DateTime.fromMillisecondsSinceEpoch(
        issuedAtMs,
        isUtc: true,
      );
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs,
        isUtc: true,
      );
      final now = _clock().toUtc();
      final lifetime = expiresAt.difference(issuedAt);
      if (issuedAt.isAfter(now) ||
          !expiresAt.isAfter(now) ||
          lifetime <= Duration.zero ||
          lifetime > tokenLifetime) {
        return null;
      }
      if (expectedSessionId != null && sessionId != expectedSessionId.trim()) {
        return null;
      }
      if (expectedClassId != null && classId != expectedClassId.trim()) {
        return null;
      }
      if (expectedWindowId != null && windowId != expectedWindowId.trim()) {
        return null;
      }

      return QrTokenClaims(
        sessionId: sessionId,
        classId: classId,
        windowId: windowId,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
      );
    } on FormatException {
      return null;
    }
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, field, '$field không được để trống.');
    }
    return normalized;
  }

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final comparedLength =
        left.length < right.length ? left.length : right.length;
    for (var index = 0; index < comparedLength; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
