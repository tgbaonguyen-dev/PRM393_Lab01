import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Process liveness only; does not check database connectivity.
class HealthController {
  Response handle(Request request) {
    if (request.url.path != 'health') {
      return Response.notFound('Not found');
    }
    if (request.method != 'GET') {
      return Response(405, headers: {'allow': 'GET'});
    }
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}
