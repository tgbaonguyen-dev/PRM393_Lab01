import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Serializes a destructive reset against every in-flight backend request.
class AppResetController {
  final String resetKey;
  final Future<void> Function(String key) reset;
  bool _resetting = false;
  int _active = 0;

  AppResetController({required this.resetKey, required this.reset});

  Middleware get middleware => (inner) => (request) async {
        if (request.url.path == 'app/reset') return _handle(request);
        if (_resetting)
          return _json(503, 'Đang xóa dữ liệu. Vui lòng thử lại sau.');
        _active++;
        try {
          return await inner(request);
        } finally {
          _active--;
        }
      };

  Future<Response> _handle(Request request) async {
    if (request.method != 'POST') return _json(405, 'Chỉ hỗ trợ POST.');
    if (resetKey.isEmpty)
      return _json(503, 'Backend chưa cấu hình APP_RESET_KEY.');
    if (request.headers['authorization'] != 'Bearer $resetKey') {
      return _json(403, 'Khóa quản trị không đúng.');
    }
    try {
      final body = jsonDecode(await request.readAsString());
      if (body is! Map || body['confirmation'] != 'DELETE_ALL_APP_DATA') {
        return _json(400, 'Thiếu xác nhận xóa toàn bộ dữ liệu.');
      }
    } catch (_) {
      return _json(400, 'Xác nhận không hợp lệ.');
    }
    if (_resetting) return _json(409, 'Một yêu cầu xóa đang được xử lý.');
    _resetting = true;
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (_active > 0) {
        if (DateTime.now().isAfter(deadline)) {
          return _json(409, 'Vẫn còn thao tác đang chạy. Chưa xóa dữ liệu.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await reset(resetKey);
      return Response.ok(jsonEncode({'success': true}), headers: _headers);
    } catch (_) {
      return _json(502,
          'Chưa xác nhận xóa hoàn tất. Kiểm tra gateway và thử lại; dữ liệu cục bộ trên máy chưa bị xóa.');
    } finally {
      _resetting = false;
    }
  }

  static const _headers = {'content-type': 'application/json; charset=utf-8'};
  static Response _json(int code, String message) => Response(code,
      body: jsonEncode({'success': false, 'error': message}),
      headers: _headers);
}
