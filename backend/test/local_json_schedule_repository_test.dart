import 'dart:io';

import 'package:backend/repositories/local_json_schedule_repository.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File testFile;
  late LocalJsonScheduleRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('schedule_test_');
    testFile = File('${tempDir.path}/schedules.json');
    repository = LocalJsonScheduleRepository(storageFile: testFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saves and retrieves a single class offering and lessons', () async {
    final offering = {
      'classId': 'PRM393_SE1917_FA26',
      'classCode': 'SE1917',
      'subjectCode': 'PRM393',
      'semester': 'FA26',
      'scheduleCode': '12',
      'lessonCount': 20,
      'active': true,
    };
    final students = [
      {
        'rollNumber': 'SE182346',
        'fullName': 'Trần Gia Bảo',
        'email': 'baotgse182346@fpt.edu.vn',
      }
    ];
    final lessons = [
      {
        'lessonId': 'PRM393_SE1917_FA26-L01',
        'sequenceNumber': 1,
        'date': '2026-09-07',
        'dailySlot': 2,
      }
    ];

    final saved = await repository.save(
      classOffering: offering,
      students: students,
      lessons: lessons,
    );

    expect(saved, isTrue);
    expect(await testFile.exists(), isTrue);

    final retrieved = await repository.get('PRM393_SE1917_FA26');
    expect(retrieved, isNotNull);
    expect(retrieved!['classOffering']['classCode'], 'SE1917');
    expect((retrieved['students'] as List), hasLength(1));
    expect((retrieved['lessons'] as List), hasLength(1));
  });

  test('saveAll stores multiple schedules and list/getAll returns active only', () async {
    final schedule1 = {
      'classOffering': {
        'classId': 'CLASS_1',
        'classCode': 'SE1901',
        'active': true,
      },
      'students': [
        {'rollNumber': 'SE111111'}
      ],
      'lessons': [],
    };
    final schedule2 = {
      'classOffering': {
        'classId': 'CLASS_2',
        'classCode': 'SE1902',
        'active': false,
      },
      'students': [],
      'lessons': [],
    };

    await repository.saveAll([schedule1, schedule2]);

    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.first['classOffering']['classId'], 'CLASS_1');

    final list = await repository.list();
    expect(list, hasLength(1));
    expect(list.first['classId'], 'CLASS_1');

    await repository.syncActiveClassIds({'CLASS_2'});

    final updatedAll = await repository.getAll();
    expect(updatedAll, hasLength(1));
    expect(updatedAll.first['classOffering']['classId'], 'CLASS_2');
  });
}
