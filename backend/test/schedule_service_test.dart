import 'package:backend/services/schedule_service.dart';
import 'package:test/test.dart';

void main() {
  test('validates and saves a 20-lesson schedule', () async {
    final repository = _FakeScheduleRepository();
    final service = ScheduleService(repository: repository);

    final result = await service.saveSchedule(_validPayload());

    expect(repository.saveCount, 1);
    expect((result['lessons'] as List), hasLength(20));
    expect(await service.getSchedule('PRM393_SE1917_FA26'), isNotNull);
  });

  test('rejects a schedule that does not contain 20 lessons', () async {
    final payload = _validPayload();
    (payload['lessons'] as List).removeLast();
    final service = ScheduleService(repository: _FakeScheduleRepository());

    expect(
      () => service.saveSchedule(payload),
      throwsA(isA<ScheduleValidationException>()),
    );
  });

  test('accepts a configured 12-lesson special subject', () async {
    final repository = _FakeScheduleRepository();
    final service = ScheduleService(repository: repository);

    final result = await service.saveSchedule(_validPayload(lessonCount: 12));

    expect((result['lessons'] as List), hasLength(12));
    expect(
      (result['classOffering'] as Map<String, dynamic>)['lessonCount'],
      12,
    );
  });

  test('does not report success when repository fails', () async {
    final service = ScheduleService(
      repository: _FakeScheduleRepository(shouldSave: false),
    );

    expect(() => service.saveSchedule(_validPayload()), throwsStateError);
  });

  test('skips unchanged classes during a batch save', () async {
    final unchanged = _validPayload();
    final changed = _validPayload();
    (changed['classOffering'] as Map<String, dynamic>)['classId'] =
        'PRM393_SE1918_FA26';
    (changed['classOffering'] as Map<String, dynamic>)['classCode'] = 'SE1918';
    for (final student in changed['students'] as List<Map<String, dynamic>>) {
      student['classCode'] = 'SE1918';
    }
    final repository = _FakeScheduleRepository(
      existingSchedules: [unchanged],
    );
    final service = ScheduleService(repository: repository);

    final saved = await service.saveSchedules([unchanged, changed]);

    expect(saved, hasLength(1));
    expect(saved.single['classOffering']['classId'], 'PRM393_SE1918_FA26');
    expect(repository.saveCount, 1);
    expect(
        repository.syncedActiveClassIds,
        containsAll([
          'PRM393_SE1917_FA26',
          'PRM393_SE1918_FA26',
        ]));
  });

  test('does not write when every class is unchanged', () async {
    final unchanged = _validPayload();
    final repository = _FakeScheduleRepository(
      existingSchedules: [unchanged],
    );
    final service = ScheduleService(repository: repository);

    final saved = await service.saveSchedules([unchanged]);

    expect(saved, isEmpty);
    expect(repository.saveCount, 0);
    expect(repository.syncCount, 1);

    final changedImport = _validPayload();
    (changedImport['classOffering'] as Map<String, dynamic>)['classId'] =
        'PRM393_SE1918_FA26';
    (changedImport['classOffering'] as Map<String, dynamic>)['classCode'] =
        'SE1918';
    for (final student
        in changedImport['students'] as List<Map<String, dynamic>>) {
      student['classCode'] = 'SE1918';
    }
    await service.saveSchedules([changedImport]);
    expect(repository.syncedActiveClassIds, contains('PRM393_SE1918_FA26'));
    expect(
        repository.syncedActiveClassIds, isNot(contains('PRM393_SE1917_FA26')));
  });

  test('falls back to upsert when comparison restore fails', () async {
    final repository = _FakeScheduleRepository(failGetAll: true);
    final service = ScheduleService(repository: repository);

    final saved = await service.saveSchedules([_validPayload()]);

    expect(saved, hasLength(1));
    expect(repository.saveCount, 1);
  });

  test('accepts an adjusted lesson moved to slot 5', () async {
    final payload = _validPayload();
    final lesson = (payload['lessons'] as List).first as Map<String, dynamic>;
    lesson
      ..['dailySlot'] = 5
      ..['startTime'] = '17:45'
      ..['endTime'] = '19:15'
      ..['isAdjusted'] = true;

    final result = await ScheduleService(
      repository: _FakeScheduleRepository(),
    ).saveSchedule(payload);

    expect((result['lessons'] as List).first['dailySlot'], 5);
  });
}

class _FakeScheduleRepository implements ScheduleRepository {
  final bool shouldSave;
  final bool failGetAll;
  final List<Map<String, dynamic>> existingSchedules;
  int saveCount = 0;
  int syncCount = 0;
  final Set<String> syncedActiveClassIds = <String>{};

  _FakeScheduleRepository({
    this.shouldSave = true,
    this.failGetAll = false,
    this.existingSchedules = const [],
  });

  @override
  Future<bool> save({
    required Map<String, dynamic> classOffering,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> lessons,
  }) async {
    saveCount++;
    return shouldSave;
  }

  @override
  Future<bool> saveAll(List<Map<String, dynamic>> schedules) async {
    saveCount += schedules.length;
    return shouldSave;
  }

  @override
  Future<bool> syncActiveClassIds(Set<String> activeClassIds) async {
    syncCount++;
    syncedActiveClassIds
      ..clear()
      ..addAll(activeClassIds);
    return shouldSave;
  }

  @override
  Future<Map<String, dynamic>?> get(String classId) async {
    for (final schedule in existingSchedules) {
      final offering = schedule['classOffering'];
      if (offering is Map && offering['classId'] == classId) return schedule;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getAll() async {
    if (failGetAll) throw StateError('restore failed');
    return existingSchedules;
  }
}

Map<String, dynamic> _validPayload({int lessonCount = 20}) {
  final firstDate = DateTime(2026, 9, 7);
  return {
    'classOffering': {
      'classId': 'PRM393_SE1917_FA26',
      'classCode': 'SE1917',
      'subjectCode': 'PRM393',
      'semester': 'FA26',
      'scheduleCode': '12',
      'sourceSheetName': '12_PRM393_SE1917',
      'lessonCount': lessonCount,
    },
    'students': [
      {
        'classCode': 'SE1917',
        'rollNumber': 'SE123456',
        'fullName': 'Student One',
        'email': 'student@example.com',
        'memberCode': 'M001',
      },
    ],
    'lessons': List.generate(lessonCount, (index) {
      final week = index ~/ 2;
      final date = firstDate.add(
        Duration(days: week * 7 + (index.isOdd ? 3 : 0)),
      );
      return {
        'lessonId': 'PRM393_SE1917_FA26-L${index + 1}',
        'sequenceNumber': index + 1,
        'date':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'dailySlot': 2,
        'startTime': '09:30',
        'endTime': '11:45',
        'status': 'scheduled',
        'isAdjusted': false,
      };
    }),
  };
}
