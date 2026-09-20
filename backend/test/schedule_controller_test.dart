import 'dart:convert';

import 'package:backend/controllers/schedule_controller.dart';
import 'package:backend/services/schedule_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('POST /save returns 400 for an invalid schedule', () async {
    final controller = ScheduleController(
      service: ScheduleService(repository: _ControllerFakeRepository()),
    );
    final response = await controller.router.call(
      Request(
        'POST',
        Uri.parse('http://localhost/save'),
        body: jsonEncode({
          'classOffering': <String, dynamic>{},
          'students': <dynamic>[],
          'lessons': <dynamic>[],
        }),
      ),
    );

    expect(response.statusCode, 400);
    expect(jsonDecode(await response.readAsString())['success'], isFalse);
  });
}

class _ControllerFakeRepository implements ScheduleRepository {
  @override
  Future<bool> save({
    required Map<String, dynamic> classOffering,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> lessons,
  }) async =>
      true;

  @override
  Future<bool> saveAll(
    List<Map<String, dynamic>> schedules, {
    bool clearPrevious = false,
  }) async =>
      true;

  @override
  Future<bool> syncActiveClassIds(
    Set<String> activeClassIds, {
    bool clearPrevious = false,
  }) async =>
      true;

  @override
  Future<Map<String, dynamic>?> get(String classId) async => null;

  @override
  Future<List<Map<String, dynamic>>> list() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAll() async => const [];
}
