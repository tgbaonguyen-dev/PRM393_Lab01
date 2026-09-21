import 'dart:async';
import 'package:backend/controllers/app_reset_controller.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Request request({String key = 'test-key', String confirmation = 'DELETE_ALL_APP_DATA'}) =>
  Request('POST', Uri.parse('http://localhost/app/reset'),
    headers: {'authorization': 'Bearer $key'}, body: '{"confirmation":"$confirmation"}');

void main() {
  test('reset requires a configured key and explicit confirmation', () async {
    var calls = 0;
    final controller = AppResetController(resetKey: 'test-key', reset: (_) async { calls++; });
    final handler = controller.middleware((_) => Response.ok('normal'));
    expect((await handler(request(key: 'wrong'))).statusCode, 403);
    expect((await handler(request(confirmation: ''))).statusCode, 400);
    expect(calls, 0);
    expect((await handler(request())).statusCode, 200);
    expect(calls, 1);
    final disabled = AppResetController(resetKey: '', reset: (_) async { calls++; });
    expect((await disabled.middleware((_) => Response.ok(''))(request())).statusCode, 503);
    expect(calls, 1);
  });

  test('waits for active writes and rejects new requests during reset', () async {
    final write = Completer<Response>();
    final resetStarted = Completer<void>();
    final resetFinished = Completer<void>();
    final controller = AppResetController(resetKey: 'test-key', reset: (_) async {
      resetStarted.complete(); await resetFinished.future;
    });
    final handler = controller.middleware((_) => write.future);
    final pendingWrite = handler(Request('POST', Uri.parse('http://localhost/schedule/save')));
    final reset = handler(request());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(resetStarted.isCompleted, false);
    expect((await handler(Request('GET', Uri.parse('http://localhost/schedule/all')))).statusCode, 503);
    write.complete(Response.ok('saved'));
    await pendingWrite;
    await resetStarted.future;
    expect((await handler(request())).statusCode, 409);
    resetFinished.complete();
    expect((await reset).statusCode, 200);
  });

  test('failure is reported rather than claiming successful reset', () async {
    final controller = AppResetController(resetKey: 'test-key', reset: (_) async { throw StateError('gateway unavailable'); });
    final handler = controller.middleware((_) => Response.ok('normal'));
    expect((await handler(request())).statusCode, 502);
    expect((await handler(Request('GET', Uri.parse('http://localhost/health')))).statusCode, 200);
  });
}
