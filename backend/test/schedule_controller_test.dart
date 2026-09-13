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
}
