import 'dart:io';

import 'package:backend/config/local_env.dart';
import 'package:backend/controllers/schedule_controller.dart';
import 'package:backend/controllers/session_controller.dart';
import 'package:backend/repositories/local_first_schedule_repository.dart';
import 'package:backend/repositories/local_json_schedule_repository.dart';
import 'package:backend/repositories/sheets_repository.dart';
import 'package:backend/services/qr_service.dart';
import 'package:backend/services/schedule_service.dart';
import 'package:backend/services/session_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final env = await LocalEnv.load();
  final sheetsRepo =
      SheetsRepository(gatewayUrl: env['APPS_SCRIPT_GATEWAY_URL']);
  final localJsonRepo = LocalJsonScheduleRepository();
  final hybridRepo = LocalFirstScheduleRepository(
    local: localJsonRepo,
    sheetsGateway: sheetsRepo,
  );
  final scheduleController = ScheduleController(
    service: ScheduleService(repository: hybridRepo),
  );
  final qrSecret = (env['QR_HMAC_SECRET'] ?? '').trim();
  final sessionController = SessionController(
    sessionService: SessionService(repository: sheetsRepo),
    qrService: QrService(
      secret: qrSecret.isNotEmpty
          ? qrSecret
          : 'dev-secret-key-prm393-attendance',
    ),
    checkInBaseUrl: env['STUDENT_CHECKIN_BASE_URL'],
  );
  final router = Router()
    ..get('/health', (Request req) => Response.ok('{"status":"ok"}', headers: {'content-type': 'application/json'}))
    ..mount('/schedule/', scheduleController.router.call)
    ..mount('/session/', sessionController.router.call);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(router.call);
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final server =
      await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
  print(
      'PRM393 backend listening on http://${server.address.host}:${server.port}');
}

Middleware _cors() => (inner) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await inner(request);
      return response.change(headers: _corsHeaders);
    };

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};
