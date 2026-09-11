import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../config.dart';

class QrValidationResult {
  final bool isValid;
  final String? lessonId;
  final String? windowId;
  final String? error;

  QrValidationResult({
    required this.isValid,
    this.lessonId,
    this.windowId,
    this.error,
  });
}

class QrService {
  final String secret;

  QrService({String? secret}) : secret = secret ?? AppConfig.qrHmacSecret;

  /// Generates a signed, time-bound QR token with HMAC-SHA256 signature (TTL: 15 seconds)
  String generateToken({
    required String lessonId,
    required String windowId,
    int ttlSeconds = 15,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = now + ttlSeconds;

    final payloadJson = jsonEncode({
      'lessonId': lessonId,
      'windowId': windowId,
      'expiresAt': expiresAt,
      'createdAt': now,
    });

    final payloadB64 = base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
    final signature = _sign(payloadB64);

    return '$payloadB64.$signature';
  }

  /// Validates signature, expiration, and format of a QR token
  QrValidationResult validateToken(String token) {
    final parts = token.split('.');
    if (parts.length != 2) {
      return QrValidationResult(isValid: false, error: 'Mã QR không đúng định dạng.');
    }

    final payloadB64 = parts[0];
    final signature = parts[1];

    final expectedSignature = _sign(payloadB64);
    if (signature != expectedSignature) {
      return QrValidationResult(isValid: false, error: 'Chữ ký mã QR không hợp lệ (nghi vấn làm giả).');
    }

    try {
      final normalized = base64Url.normalize(payloadB64);
      final jsonStr = utf8.decode(base64Url.decode(normalized));
      final dynamic payload = jsonDecode(jsonStr);

      if (payload is! Map<String, dynamic>) {
        return QrValidationResult(isValid: false, error: 'Nội dung mã QR bị lỗi.');
      }

      final expiresAt = payload['expiresAt'] as int? ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Allow 2-second grace period for clock skew
      if (now > expiresAt + 2) {
        return QrValidationResult(isValid: false, error: 'Mã QR đã hết hạn (quá 15 giây). Vui lòng quét mã mới.');
      }

      return QrValidationResult(
        isValid: true,
        lessonId: payload['lessonId'] as String?,
        windowId: payload['windowId'] as String?,
      );
    } catch (_) {
      return QrValidationResult(isValid: false, error: 'Giải mã QR thất bại.');
    }
  }

  String _sign(String data) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(data));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
