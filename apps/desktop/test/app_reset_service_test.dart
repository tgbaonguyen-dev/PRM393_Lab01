import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prm393_desktop/features/settings/app_reset_service.dart';

void main() {
  test('remote errors are not reported as success', () async {
    final service = AppResetService(client: MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer test-key');
      expect(request.body, contains('DELETE_ALL_APP_DATA'));
      return http.Response('{"success":false,"error":"Denied"}', 403);
    }));
    await expectLater(service.resetRemote('test-key'), throwsStateError);
    service.dispose();
  });

  test('local reset clears only app data inside the detected project', () async {
    final temp = await Directory.systemTemp.createTemp('ipresent-reset-test-');
    addTearDown(() => temp.delete(recursive: true));
    final project = Directory('${temp.path}/project');
    Future<File> put(String path, String value) async {
      final file = File(path); await file.parent.create(recursive: true);
      return file.writeAsString(value);
    }
    await put('${project.path}/apps/desktop/pubspec.yaml', 'name: test');
    final attendance = await put('${project.path}/apps/desktop/attendance_database.json', '{"old":1}');
    final schedule = await put('${project.path}/backend/data/schedules_local.json', '{"old":1}');
    final workbook = await put('${project.path}/markbook.xlsx', 'source');
    final outside = await put('${temp.path}/attendance_database.json', 'unrelated');
    final service = AppResetService();
    await service.resetLocal(directory: Directory('${project.path}/apps/desktop'));
    expect(await attendance.readAsString(), '{}');
    expect(await schedule.readAsString(), contains('"classes":{}'));
    expect(await workbook.readAsString(), 'source');
    expect(await outside.readAsString(), 'unrelated');
    service.dispose();
  });
}
