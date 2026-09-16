import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import '../lib/controllers/attendance_controller.dart';
import '../lib/controllers/session_controller.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final router = Router();
  final attendanceController = AttendanceController();
  final sessionController = SessionController();

  router.get(
      '/',
      (Request request) => Response.ok(
            jsonEncode({
              'status': 'online',
              'service': 'PRM393 attendance backend',
              'endpoints': ['POST /attendance/checkin'],
            }),
            headers: {'content-type': 'application/json'},
          ));
  router.mount('/', attendanceController.router.call);
  router.mount('/attendance', attendanceController.router.call);
  router.mount('/', sessionController.router.call);

  final handler = Pipeline()
      .addMiddleware(corsHeaders())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Backend listening on http://${server.address.host}:${server.port}');
}
