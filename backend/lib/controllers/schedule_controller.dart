import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/schedule_service.dart';

class ScheduleController {
  final ScheduleService _service;

  ScheduleController({ScheduleService? service})
      : _service = service ?? ScheduleService();

  Router get router {
    final router = Router();
    router.post('/save', _save);
    router.get('/', _list);
    router.get('/<classId>', _get);
    return router;
  }

  Future<Response> _save(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      if (decoded is! Map)
        return _json(400, {'error': 'JSON request không hợp lệ.'});
      final schedule = await _service.saveSchedule(
        Map<String, dynamic>.from(decoded),
      );
      return _json(200, {
        'success': true,
        'message': 'Đã lưu lịch 20 buổi.',
        'data': schedule,
      });
    } on FormatException catch (error) {
      return _json(400, {
        'success': false,
        'error': 'JSON không hợp lệ: ${error.message}',
      });
    } on ScheduleValidationException catch (error) {
      return _json(400, {'success': false, 'error': error.message});
    } on StateError catch (error) {
      return _json(502, {'success': false, 'error': error.message});
    } catch (_) {
      return _json(500, const {
        'success': false,
        'error': 'Không thể lưu lịch do lỗi máy chủ.',
      });
    }
  }

  Future<Response> _list(Request request) async {
    try {
      final schedules = await _service.listSchedules();
      return _json(200, {'success': true, 'data': schedules});
    } catch (_) {
      return _json(
          502, const {'success': false, 'error': 'Không thể tải lịch đã lưu.'});
    }
  }

  Future<Response> _get(Request request, String classId) async {
    final schedule = await _service.getSchedule(Uri.decodeComponent(classId));
    if (schedule == null) {
      return _json(404, {
        'success': false,
        'error': 'Không tìm thấy lịch của lớp.',
      });
    }
    return _json(200, {'success': true, 'data': schedule});
  }

  static Response _json(int statusCode, Map<String, dynamic> body) => Response(
        statusCode,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
}
