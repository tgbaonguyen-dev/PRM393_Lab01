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
}
