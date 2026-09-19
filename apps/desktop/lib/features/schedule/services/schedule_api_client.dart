import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../config.dart';
import '../../import/models/import_models.dart';
import '../models/schedule_models.dart';

class ScheduleApiClient {
  static const _requestTimeout = Duration(seconds: 60);
  static const _availabilityTimeout = Duration(seconds: 20);

  final String baseUrl;
  final http.Client _client;

  ScheduleApiClient({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
      _client = client ?? http.Client();

  Future<String> saveSchedule({
    required ImportedClass importedClass,
    required List<ClassLesson> lessons,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/schedule/save'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'classOffering': {
          'classId': importedClass.offeringId,
          'classCode': importedClass.classCode,
          'subjectCode': importedClass.subjectCode,
          'semester': importedClass.semester,
          'scheduleCode': importedClass.scheduleCode,
          'sourceSheetName': importedClass.sourceSheetName,
          'lessonCount': importedClass.lessonCount,
        },
        'students': importedClass.students
            .map((student) => student.toJson())
            .toList(),
        'lessons': lessons.map((lesson) => lesson.toJson()).toList(),
      }),
    );
    final decoded = jsonDecode(response.body);
    final body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['error'] ?? 'Backend trả về HTTP ${response.statusCode}.',
      );
    }
    return body['message'] as String? ?? 'Đã lưu lịch thành công.';
  }

  Future<String> saveSchedules({
    required List<ImportedClass> importedClasses,
    required Map<String, List<ClassLesson>> schedules,
  }) async {
    final response = await _send(
      _client.post(
        Uri.parse('$baseUrl/schedule/save-all'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'activeClassIds': importedClasses
              .map((importedClass) => importedClass.offeringId)
              .toList(),
          'schedules': importedClasses
              .map(
                (importedClass) => {
                  'classOffering': {
                    'classId': importedClass.offeringId,
                    'classCode': importedClass.classCode,
                    'subjectCode': importedClass.subjectCode,
                    'semester': importedClass.semester,
                    'scheduleCode': importedClass.scheduleCode,
                    'sourceSheetName': importedClass.sourceSheetName,
                    'lessonCount': importedClass.lessonCount,
                  },
                  'students': importedClass.students
                      .map((student) => student.toJson())
                      .toList(),
                  'lessons':
                      (schedules[importedClass.sourceSheetName] ?? const [])
                          .map((lesson) => lesson.toJson())
                          .toList(),
                },
              )
              .toList(),
        }),
      ),
    );
    final body = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Không thể lưu lịch.');
    }
    return body['message'] as String? ?? 'Đã lưu lịch thành công.';
  }

  Future<List<Map<String, dynamic>>> listSchedules() async {
    final response = await _send(
      _client.get(Uri.parse('$baseUrl/schedule/')),
      timeout: _availabilityTimeout,
    );
    final body = _decode(response);
    if (response.statusCode != 200) {
      throw Exception(body['error'] ?? 'Không thể tải lịch.');
    }
    final data = body['data'];
    return data is List
        ? data.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const [];
  }

  Future<SavedSchedules> loadSavedSchedules() async {
    try {
      final response = await _send(
        _client.get(Uri.parse('$baseUrl/schedule/all')),
        timeout: const Duration(seconds: 2),
      );
      final body = _decode(response);
      if (response.statusCode == 200 && body['data'] is List) {
        final saved = _savedSchedulesFromData(body['data'] as List);
        if (saved.classes.isNotEmpty) return saved;
      }
    } catch (_) {}

    // Fallback: Nạp trực tiếp từ file JSON lưu trữ cục bộ nếu backend chưa kịp mở
    final local = loadLocalSchedules();
    if (local != null && local.classes.isNotEmpty) {
      return local;
    }
    return const SavedSchedules(classes: [], schedules: {});
  }

  SavedSchedules? loadLocalSchedules() {
    final candidatePaths = [
      '../../backend/data/schedules_local.json',
      '../backend/data/schedules_local.json',
      'backend/data/schedules_local.json',
      'schedules_local.json',
    ];
    for (final path in candidatePaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final content = file.readAsStringSync();
          final decoded = jsonDecode(content);
          if (decoded is Map && decoded['classes'] is Map) {
            final list = (decoded['classes'] as Map).values.toList();
            return _savedSchedulesFromData(list);
          }
        } catch (_) {}
      }
    }

    // Walk up from Directory.current
    try {
      Directory? dir = Directory.current;
      for (var i = 0; i < 5 && dir != null; i++) {
        final target = File('${dir.path}${Platform.pathSeparator}backend${Platform.pathSeparator}data${Platform.pathSeparator}schedules_local.json');
        if (target.existsSync()) {
          final content = target.readAsStringSync();
          final decoded = jsonDecode(content);
          if (decoded is Map && decoded['classes'] is Map) {
            final list = (decoded['classes'] as Map).values.toList();
            return _savedSchedulesFromData(list);
          }
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}

    return null;
  }

  SavedSchedules _savedSchedulesFromData(List data) {
    final classes = <ImportedClass>[];
    final schedules = <String, List<ClassLesson>>{};
    for (final rawSchedule in data.whereType<Map>()) {
      final schedule = Map<String, dynamic>.from(rawSchedule);
      if (schedule['classOffering'] is! Map) continue;
      final offering = Map<String, dynamic>.from(
        schedule['classOffering'] as Map,
      );
      if (offering['active'] == false) continue;
      final students = (schedule['students'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ImportedStudent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      final importedClass = ImportedClass.fromStorage(offering, students);
      final lessons = (schedule['lessons'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ClassLesson.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      classes.add(importedClass);
      schedules[importedClass.sourceSheetName] = lessons;
    }
    return SavedSchedules(classes: classes, schedules: schedules);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  Future<http.Response> _send(
    Future<http.Response> request, {
    Duration timeout = _requestTimeout,
  }) async {
    try {
      return await request.timeout(timeout);
    } on TimeoutException {
      throw Exception(
        'Backend không phản hồi sau ${timeout.inSeconds} giây. '
        'Hãy kiểm tra backend đang chạy tại $baseUrl.',
      );
    }
  }
}

class SavedSchedules {
  final List<ImportedClass> classes;
  final Map<String, List<ClassLesson>> schedules;

  const SavedSchedules({required this.classes, required this.schedules});

  DateTime get firstLessonDate {
    final allLessons = schedules.values.expand((lessons) => lessons).toList();
    if (allLessons.isEmpty) return DateTime.now();
    return allLessons
        .map((lesson) => lesson.date)
        .reduce((left, right) => left.isBefore(right) ? left : right);
  }
}
