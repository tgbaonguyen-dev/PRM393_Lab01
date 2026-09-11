import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../repositories/data_gateway_repository.dart';

class ClassController {
  final DataGatewayRepository repo;

  ClassController({DataGatewayRepository? repo}) : repo = repo ?? DataGatewayRepository();

  Router get router {
    final router = Router();

    // POST /api/class/sync
    router.post('/sync', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr) as Map<String, dynamic>;
        final classes = body['classes'] as List<dynamic>?;
        final startDate = body['startDate'] as String? ?? '';

        if (classes != null && classes.isNotEmpty) {
          final res = await repo.syncAllClasses(classes, startDate);
          return Response.ok(
            jsonEncode(res),
            headers: {'content-type': 'application/json'},
          );
        }

        return Response(400,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Dữ liệu classes không hợp lệ hoặc trống'}));
      } catch (e) {
        return Response(500,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'error': 'Lỗi đồng bộ danh sách lớp: $e'}));
      }
    });

    return router;
  }
}
