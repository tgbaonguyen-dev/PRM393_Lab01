import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:prm393_backend/controllers/health_controller.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final fileEnv = DotEnv();
  if (File('.env').existsSync()) fileEnv.load();
  // Hosting environment variables take precedence over local configuration.
  String? setting(String name) => Platform.environment[name] ?? fileEnv[name];

  final port = int.tryParse(setting('PORT') ?? '8080');
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('PORT must be an integer between 1 and 65535.');
    exitCode = 1;
    return;
  }

  final server = await shelf_io.serve(
    HealthController().handle,
    setting('HOST') ?? '127.0.0.1',
    port,
  );
  stdout.writeln(
    'Backend running at http://${server.address.host}:${server.port}',
  );
}
