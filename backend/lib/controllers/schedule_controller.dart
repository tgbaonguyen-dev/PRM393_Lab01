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
    router.post('/save-all', _saveAll);
    router.get('/all', _getAll);
    router.get('/', _list);
    router.get('/<classId>', _get);
    return router;
  }

  Future<Response> _saveAll(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      if (decoded is! Map || decoded['schedules'] is! List) {
        return _json(400, {'error': 'Danh sách schedules không hợp lệ.'});
      }
      final schedules = (decoded['schedules'] as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
      Set<String>? activeClassIds;
      if (decoded.containsKey('activeClassIds')) {
        if (decoded['activeClassIds'] is! List) {
          return _json(400, {
            'success': false,
            'error': 'activeClassIds không hợp lệ.',
          });
        }
        activeClassIds = (decoded['activeClassIds'] as List)
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet();
      }
      final clearPrevious = decoded['clearPrevious'] == true;
      final saved = await _service.saveSchedules(
        schedules,
        activeClassIds: activeClassIds,
        clearPrevious: clearPrevious,
      );
      final skippedCount = schedules.length - saved.length;
      final message = saved.isEmpty && activeClassIds != null
          ? 'Đã đồng bộ ${activeClassIds.length} lớp lên Google Sheet.'
          : skippedCount == 0
              ? 'Đã lưu và đồng bộ ${saved.length} lớp lên Google Sheet.'
              : saved.isEmpty
                  ? 'Đã đồng bộ ${schedules.length} lớp lên Google Sheet.'
                  : 'Đã lưu ${saved.length} lớp mới và đồng bộ toàn bộ ${activeClassIds?.length ?? schedules.length} lớp lên Google Sheet.';
      return _json(200, {
        'success': true,
        'message': message,
        'data': {
          'requestedCount': schedules.length,
          'savedCount': saved.length,
          'skippedCount': skippedCount,
          'activeClassCount': activeClassIds?.length ?? schedules.length,
        },
      });
    } on FormatException catch (error) {
      return _json(400, {'success': false, 'error': error.message});
    } on ScheduleValidationException catch (error) {
      return _json(400, {'success': false, 'error': error.message});
    } on StateError catch (error) {
      return _json(502, {'success': false, 'error': error.message});
    } catch (error) {
      return _json(500, {'success': false, 'error': '$error'});
    }
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
    } catch (error) {
      // M1 is still being integrated with a separately deployed gateway.
      // Preserve the actual error so an invalid imported class can be fixed
      // instead of making every failure look like a server outage.
      return _json(500, {
        'success': false,
        'error': 'Không thể lưu lịch do lỗi máy chủ: $error',
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

  Future<Response> _getAll(Request request) async {
    try {
      final schedules = await _service.getAllSchedules();
      return _json(200, {'success': true, 'data': schedules});
    } on StateError catch (error) {
      return _json(502, {'success': false, 'error': error.message});
    } catch (_) {
      return _json(
          502, const {'success': false, 'error': 'Không thể tải lịch.'});
    }
  }

  static Response _json(int statusCode, Map<String, dynamic> body) => Response(
        statusCode,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
}
