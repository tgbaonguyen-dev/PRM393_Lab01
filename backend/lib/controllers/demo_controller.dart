import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../services/demo_service.dart';

class DemoController {
  DemoController(this._service);

  final DemoService _service;

  Response handle(Request request) {
    if (request.method != 'GET') {
      return Response(405, headers: {'allow': 'GET'});
    }
    return Response.ok(
      jsonEncode(_service.getMessage()),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
      },
    );
  }
}
