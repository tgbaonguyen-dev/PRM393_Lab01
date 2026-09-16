import 'dart:io';

import 'package:backend/repositories/local_first_schedule_repository.dart';
import 'package:backend/repositories/local_json_schedule_repository.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File testFile;
  late LocalJsonScheduleRepository localRepo;
  late LocalFirstScheduleRepository hybridRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hybrid_test_');
    testFile = File('${tempDir.path}/schedules.json');
    localRepo = LocalJsonScheduleRepository(storageFile: testFile);
    hybridRepo = LocalFirstScheduleRepository(
      local: localRepo,
      sheetsGateway: null, // Test purely offline/local-first
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saves and loads immediately from local repository without remote gateway', () async {
    final schedule = {
      'classOffering': {
        'classId': 'PRM393_SE1917_FA26',
        'classCode': 'SE1917',
        'subjectCode': 'PRM393',
        'semester': 'FA26',
        'active': true,
      },
      'students': [],
      'lessons': [],
    };

    final saved = await hybridRepo.saveAll([schedule]);
    expect(saved, isTrue);

    final all = await hybridRepo.getAll();
    expect(all, hasLength(1));
    expect(all.first['classOffering']['classId'], 'PRM393_SE1917_FA26');

    final list = await hybridRepo.list();
    expect(list, hasLength(1));
    expect(list.first['classId'], 'PRM393_SE1917_FA26');
  });
}
