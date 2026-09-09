import 'package:shelf/shelf.dart';

import 'controllers/demo_controller.dart';
import 'controllers/health_controller.dart';
import 'services/demo_service.dart';

Handler createApp({String frontendOrigin = 'http://localhost:3000'}) {
  final demo = DemoController(DemoService());
  final health = HealthController();

  return (Request request) {
    final origin = request.headers['origin'];
    final corsHeaders = <String, String>{
      'vary': 'Origin',
      if (origin == frontendOrigin) ...{
        'access-control-allow-origin': frontendOrigin,
        'access-control-allow-methods': 'GET, OPTIONS',
        'access-control-allow-headers': 'Content-Type',
      },
    };

    if (request.method == 'OPTIONS') {
      return Response(
        origin == frontendOrigin ? 204 : 403,
        headers: corsHeaders,
      );
    }

    final response = switch (request.url.path) {
      'health' => health.handle(request),
      'api/demo' => demo.handle(request),
      _ => Response.notFound('Not found'),
    };
    return response.change(headers: corsHeaders);
  };
}
