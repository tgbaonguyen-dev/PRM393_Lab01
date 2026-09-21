import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prm393_desktop/features/attendance/services/attendance_storage_service.dart';

void main() {
  test('latest report snapshot replaces stale P with server A and removes stale aliases', () async {
    final dir = await Directory.systemTemp.createTemp('ipresent-latest-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/attendance.json');
    await file.writeAsString('{"PRM393 - SE1917":{"1":{"a@example.com":"P"}}}');
    final service = AttendanceStorageService(file.path, MockClient((_) async =>
      http.Response('{"success":true,"data":{"12_PRM393_SE1917":{"1":{"a@example.com":"A"}}}}', 200)));
    final latest = await service.fetchLatestStore();
    expect(latest.containsKey('PRM393 - SE1917'), false);
    expect(AttendanceStorageService.resolveClassAttendance(store: latest,
      scheduleCode: '12', subjectCode: 'PRM393', classCode: 'SE1917')[1]!['a@example.com'], 'A');
  });

  test('failed fresh fetch preserves the existing cache and throws', () async {
    final dir = await Directory.systemTemp.createTemp('ipresent-latest-error-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/attendance.json');
    await file.writeAsString('{"keep":{}}');
    final service = AttendanceStorageService(file.path, MockClient((_) async =>
      http.Response('{"success":false}', 502)));
    await expectLater(service.fetchLatestStore(), throwsStateError);
    expect(await file.readAsString(), '{"keep":{}}');
  });
}
