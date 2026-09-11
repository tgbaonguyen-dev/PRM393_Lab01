import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/qr_service.dart';

class QrController {
  final QrService qrService;

  QrController({QrService? qrService}) : qrService = qrService ?? QrService();

  Router get router {
    final router = Router();

    // POST /api/qr/generate
    router.post('/generate', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final lessonId = body['lessonId'] as String?;
        final windowId = body['windowId'] as String?;
        final ttl = body['ttlSeconds'] as int? ?? 15;

        if (lessonId == null || windowId == null) {
          return Response(400,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({'error': 'Thiếu lessonId hoặc windowId'}));
        }

        final token = qrService.generateToken(
          lessonId: lessonId,
          windowId: windowId,
          ttlSeconds: ttl,
        );

        return Response.ok(
          jsonEncode({
            'success': true,
            'qrToken': token,
            'ttlSeconds': ttl,
            'expiresAt': DateTime.now().add(Duration(seconds: ttl)).toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(500,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Lỗi tạo mã QR: $e'}));
      }
    });

    return router;
  }
}
