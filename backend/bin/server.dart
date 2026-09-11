import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:backend/config.dart';
import 'package:backend/controllers/attendance_controller.dart';
import 'package:backend/controllers/class_controller.dart';
import 'package:backend/controllers/health_controller.dart';
import 'package:backend/controllers/qr_controller.dart';

void main(List<String> args) async {
  final ip = InternetAddress.anyIPv4;
  final port = AppConfig.port;

  final router = Router();

  // Root welcome
  router.get('/', (Request request) {
    return Response.ok(
      jsonEncode({
        'name': 'PRM393 Attendance System Dart Shelf Backend',
        'status': 'running',
        'version': '1.0.0',
        'architecture': 'Three-Layer (Controller - Service - Repository)',
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // Mount 3-layer controllers under /api
  router.mount('/api/attendance', AttendanceController().router.call);
  router.mount('/api/class', ClassController().router.call);
  router.mount('/api/qr', QrController().router.call);
  router.mount('/api', HealthController().router.call);

  // Configure middleware pipeline: CORS -> Logger -> Router
  final handler = Pipeline()
      .addMiddleware(corsHeaders(
        headers: {
          ACCESS_CONTROL_ALLOW_ORIGIN: '*',
          ACCESS_CONTROL_ALLOW_METHODS: 'GET, POST, PUT, DELETE, OPTIONS',
          ACCESS_CONTROL_ALLOW_HEADERS: 'Origin, Content-Type, Accept, Authorization',
        },
      ))
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final server = await serve(handler, ip, port);
  print('========================================================');
  print('🚀 PRM393 DART SHELF BACKEND RUNNING AT:');
  print('👉 Local: http://localhost:${server.port}');
  print('👉 Network: http://${ip.address}:${server.port}');
  print('👉 Architecture: Three-Layer (Controller - Service - Repository)');
  print('========================================================');
}
