import '../repositories/sheets_repository.dart';

abstract class ScheduleRepository {
  Future<bool> save({
    required Map<String, dynamic> classOffering,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> lessons,
  });

  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>?> get(String classId);
}

class SheetsScheduleRepository implements ScheduleRepository {
  final SheetsRepository _repository;

  SheetsScheduleRepository([SheetsRepository? repository])
      : _repository = repository ?? SheetsRepository();

  @override
  Future<bool> save({
    required Map<String, dynamic> classOffering,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> lessons,
  }) {
    return _repository.saveClassOffering(
      offering: classOffering,
      roster: students,
      lessons: lessons,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> list() => _repository.listSchedules();

  @override
  Future<Map<String, dynamic>?> get(String classId) =>
      _repository.getSchedule(classId);
}

class ScheduleValidationException implements Exception {
  final String message;

  const ScheduleValidationException(this.message);

  @override
  String toString() => message;
}

class ScheduleService {
  final ScheduleRepository _repository;
  final Map<String, Map<String, dynamic>> _cache = {};

  ScheduleService({ScheduleRepository? repository})
      : _repository = repository ?? SheetsScheduleRepository();

  Future<Map<String, dynamic>> saveSchedule(
    Map<String, dynamic> payload,
  ) async {
    final classOffering = _map(payload['classOffering'], 'classOffering');
    final students = _mapList(payload['students'], 'students');
    final lessons = _mapList(payload['lessons'], 'lessons');

    final normalizedOffering = _normalizeOffering(classOffering);
    final normalizedStudents = _normalizeStudents(
      students,
      normalizedOffering['classCode'] as String,
    );
    final normalizedLessons = _normalizeAndValidateLessons(
      lessons,
      normalizedOffering['scheduleCode'] as String,
      normalizedOffering['lessonCount'] as int,
    );
    final classId = normalizedOffering['classId'] as String;

    final saved = await _repository.save(
      classOffering: normalizedOffering,
      students: normalizedStudents,
      lessons: normalizedLessons,
    );
    if (!saved) {
      throw StateError('Repository không lưu được lịch.');
    }

    final schedule = <String, dynamic>{
      'classOffering': normalizedOffering,
      'students': normalizedStudents,
      'lessons': normalizedLessons,
    };
    _cache[classId] = schedule;
    return schedule;
  }

  Future<Map<String, dynamic>?> getSchedule(String classId) async {
    final key = classId.trim();
    final stored = await _repository.get(key);
    if (stored != null) _cache[key] = stored;
    return stored ?? _cache[key];
  }

  Future<List<Map<String, dynamic>>> listSchedules() => _repository.list();

  Map<String, dynamic> _normalizeOffering(Map<String, dynamic> input) {
    final fields = <String, String>{
      'classId': _string(input['classId']),
      'classCode': _string(input['classCode']).toUpperCase(),
      'subjectCode': _string(input['subjectCode']).toUpperCase(),
      'semester': _string(input['semester']).toUpperCase(),
      'scheduleCode': _string(input['scheduleCode']),
      'sourceSheetName': _string(input['sourceSheetName']),
    };
    for (final entry in fields.entries) {
      if (entry.value.isEmpty) {
        throw ScheduleValidationException('classOffering thiếu ${entry.key}.');
      }
    }
    if (!RegExp(r'^[123][1-5]$').hasMatch(fields['scheduleCode']!)) {
      throw const ScheduleValidationException('scheduleCode không hợp lệ.');
    }
    final lessonCount = input['lessonCount'] ?? 20;
    if (lessonCount is! int || lessonCount < 1 || lessonCount > 60) {
      throw const ScheduleValidationException(
        'lessonCount phải là số nguyên từ 1 đến 60.',
      );
    }
    return <String, dynamic>{...fields, 'lessonCount': lessonCount};
  }

  List<Map<String, dynamic>> _normalizeStudents(
    List<Map<String, dynamic>> students,
    String classCode,
  ) {
    if (students.isEmpty) {
      throw const ScheduleValidationException(
        'Danh sách sinh viên không được trống.',
      );
    }
    final seenRolls = <String>{};
    final seenEmails = <String>{};
    return students.map((student) {
      final rollNumber = _string(student['rollNumber']).toUpperCase();
      final email = _string(student['email']).toLowerCase();
      final fullName = _string(student['fullName']);
      final memberCode = _string(student['memberCode']);
      final studentClass = _string(student['classCode']).toUpperCase();
      if ([
        rollNumber,
        email,
        fullName,
        memberCode,
        studentClass,
      ].any((value) => value.isEmpty)) {
        throw const ScheduleValidationException(
          'Sinh viên thiếu trường bắt buộc.',
        );
      }
      if (studentClass != classCode) {
        throw ScheduleValidationException(
          'Sinh viên $rollNumber không thuộc lớp $classCode.',
        );
      }
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        throw ScheduleValidationException('Email $email không hợp lệ.');
      }
      if (!seenRolls.add(rollNumber)) {
        throw ScheduleValidationException('Trùng RollNumber $rollNumber.');
      }
      if (!seenEmails.add(email)) {
        throw ScheduleValidationException('Trùng email $email.');
      }
      return <String, dynamic>{
        'classCode': studentClass,
        'rollNumber': rollNumber,
        'fullName': fullName,
        'email': email,
        'memberCode': memberCode,
      };
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _normalizeAndValidateLessons(
    List<Map<String, dynamic>> lessons,
    String scheduleCode,
    int expectedLessonCount,
  ) {
    if (lessons.length != expectedLessonCount) {
      throw ScheduleValidationException(
        'Lịch phải có đúng $expectedLessonCount buổi.',
      );
    }
    final ids = <String>{};
    final dates = <String>{};
    DateTime? previousDate;
    final normalized = <Map<String, dynamic>>[];
    final expectedSlot = int.parse(scheduleCode[1]);
    final slotTimes = const <int, (String, String)>{
      1: ('07:00', '09:15'),
      2: ('09:30', '11:45'),
      3: ('12:30', '14:45'),
      4: ('15:00', '17:15'),
      5: ('17:45', '19:15'),
    };
    final expectedWeekdays = switch (scheduleCode[0]) {
      '1' => const [DateTime.monday, DateTime.thursday],
      '2' => const [DateTime.tuesday, DateTime.friday],
      _ => const [DateTime.wednesday, DateTime.saturday],
    };

    for (var index = 0; index < lessons.length; index++) {
      final lesson = lessons[index];
      final expectedSequence = index + 1;
      final sequence = lesson['sequenceNumber'];
      final lessonId = _string(lesson['lessonId']);
      final dateText = _string(lesson['date']);
      final slot = lesson['dailySlot'];
      final startTime = _string(lesson['startTime']);
      final endTime = _string(lesson['endTime']);
      final isAdjusted = lesson['isAdjusted'] == true;
      if (sequence != expectedSequence) {
        throw ScheduleValidationException(
          'sequenceNumber phải liên tục từ 1 đến $expectedLessonCount; sai tại buổi $expectedSequence.',
        );
      }
      if (lessonId.isEmpty || !ids.add(lessonId)) {
        throw ScheduleValidationException(
          'lessonId trống hoặc trùng tại buổi $expectedSequence.',
        );
      }
      final date = DateTime.tryParse(dateText);
      if (date == null || _dateOnly(date) != dateText) {
        throw ScheduleValidationException(
          'Ngày của buổi $expectedSequence không hợp lệ.',
        );
      }
      if (!dates.add(dateText)) {
        throw ScheduleValidationException('Trùng ngày học $dateText.');
      }
      if (previousDate != null && !date.isAfter(previousDate)) {
        throw const ScheduleValidationException(
          'Các buổi phải theo thứ tự thời gian.',
        );
      }
      final expectedTimes = slot is int ? slotTimes[slot] : null;
      if (expectedTimes == null) {
        throw ScheduleValidationException(
          'Ca học của buổi $expectedSequence phải từ Slot 1 đến Slot 5.',
        );
      }
      if (!isAdjusted && slot != expectedSlot) {
        throw ScheduleValidationException(
          'Ca học của buổi $expectedSequence không khớp mã lịch $scheduleCode.',
        );
      }
      if (startTime != expectedTimes.$1 || endTime != expectedTimes.$2) {
        throw ScheduleValidationException(
          'Giờ học của buổi $expectedSequence không khớp ca $expectedSlot.',
        );
      }
      if (!isAdjusted && !expectedWeekdays.contains(date.weekday)) {
        throw ScheduleValidationException(
          'Buổi $expectedSequence không thuộc cặp thứ của mã lịch $scheduleCode.',
        );
      }
      previousDate = date;
      normalized.add({
        'lessonId': lessonId,
        'sequenceNumber': sequence,
        'date': dateText,
        'dailySlot': slot,
        'startTime': startTime,
        'endTime': endTime,
        'status': 'scheduled',
        'isAdjusted': isAdjusted,
      });
    }
    return normalized;
  }

  static Map<String, dynamic> _map(dynamic value, String field) {
    if (value is! Map)
      throw ScheduleValidationException('$field không hợp lệ.');
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _mapList(dynamic value, String field) {
    if (value is! List)
      throw ScheduleValidationException('$field không hợp lệ.');
    return value.map((item) => _map(item, field)).toList();
  }

  static String _string(dynamic value) => value is String ? value.trim() : '';
  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
