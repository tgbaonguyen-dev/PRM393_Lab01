import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config.dart';
import '../../import/models/import_models.dart';
import '../models/schedule_models.dart';

class ScheduleApiClient {
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

  Future<List<Map<String, dynamic>>> listSchedules() async {
    final response = await _client.get(Uri.parse('$baseUrl/schedule/'));
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
    final summaries = await listSchedules();
    final classes = <ImportedClass>[];
    final schedules = <String, List<ClassLesson>>{};
    for (final summary in summaries) {
      final classId = summary['classId'] as String?;
      if (classId == null || classId.isEmpty) continue;
      final response = await _client.get(
        Uri.parse('$baseUrl/schedule/${Uri.encodeComponent(classId)}'),
      );
      final body = _decode(response);
      if (response.statusCode != 200 || body['data'] is! Map) {
        throw Exception(body['error'] ?? 'Không thể tải lịch $classId.');
      }
      final data = Map<String, dynamic>.from(body['data'] as Map);
      final offering = Map<String, dynamic>.from(data['classOffering'] as Map);
      final students = (data['students'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => ImportedStudent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      final importedClass = ImportedClass.fromStorage(offering, students);
      final lessons = (data['lessons'] as List? ?? const [])
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
}

class SavedSchedules {
  final List<ImportedClass> classes;
  final Map<String, List<ClassLesson>> schedules;

  const SavedSchedules({required this.classes, required this.schedules});

  DateTime get firstLessonDate => schedules.values
      .expand((lessons) => lessons)
      .map((lesson) => lesson.date)
      .reduce((left, right) => left.isBefore(right) ? left : right);
}
