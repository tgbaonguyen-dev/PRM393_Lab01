import 'dart:convert';
import 'dart:io';

import '../services/schedule_service.dart';

class LocalJsonScheduleRepository implements ScheduleRepository {
  final File file;

  LocalJsonScheduleRepository({File? storageFile})
      : file = storageFile ?? File('data/schedules_local.json');

  Future<void> resetAll() =>
      _writeRaw({'classes': <String, dynamic>{}, 'activeClassIds': <String>[]});

  Future<void> _ensureParent() async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
  }

  Future<Map<String, dynamic>> _readRaw() async {
    if (!await file.exists()) {
      return {'updatedAt': null, 'classes': <String, dynamic>{}};
    }
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return {'updatedAt': null, 'classes': <String, dynamic>{}};
      }
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        final classes = decoded['classes'];
        return {
          'updatedAt': decoded['updatedAt']?.toString(),
          'classes': classes is Map
              ? Map<String, dynamic>.from(classes)
              : <String, dynamic>{},
        };
      }
    } catch (_) {
      // If corrupted, fallback safely
    }
    return {'updatedAt': null, 'classes': <String, dynamic>{}};
  }

  Future<void> _writeRaw(Map<String, dynamic> data) async {
    await _ensureParent();
    data['updatedAt'] = DateTime.now().toIso8601String();
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(jsonString, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  @override
  Future<bool> save({
    required Map<String, dynamic> classOffering,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> lessons,
  }) async {
    final classId = classOffering['classId']?.toString();
    if (classId == null || classId.isEmpty) return false;

    final data = await _readRaw();
    final classes = Map<String, dynamic>.from(data['classes'] as Map);
    classes[classId] = {
      'classOffering': Map<String, dynamic>.from(classOffering),
      'students': students.map((s) => Map<String, dynamic>.from(s)).toList(),
      'lessons': lessons.map((l) => Map<String, dynamic>.from(l)).toList(),
    };
    data['classes'] = classes;
    await _writeRaw(data);
    return true;
  }

  @override
  Future<bool> saveAll(
    List<Map<String, dynamic>> schedules, {
    bool clearPrevious = false,
  }) async {
    if (schedules.isEmpty && !clearPrevious) return true;
    final data = await _readRaw();
    final classes = clearPrevious
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(data['classes'] as Map);

    for (final item in schedules) {
      final offering = item['classOffering'] ?? item['offering'];
      if (offering is! Map) continue;
      final classId = offering['classId']?.toString();
      if (classId == null || classId.isEmpty) continue;

      final rosterRaw = item['students'] ?? item['roster'];
      final students = rosterRaw is List
          ? rosterRaw
              .whereType<Map>()
              .map((s) => Map<String, dynamic>.from(s))
              .toList()
          : <Map<String, dynamic>>[];

      final lessonsRaw = item['lessons'];
      final lessons = lessonsRaw is List
          ? lessonsRaw
              .whereType<Map>()
              .map((l) => Map<String, dynamic>.from(l))
              .toList()
          : <Map<String, dynamic>>[];

      classes[classId] = {
        'classOffering': Map<String, dynamic>.from(offering),
        'students': students,
        'lessons': lessons,
      };
    }

    data['classes'] = classes;
    await _writeRaw(data);
    return true;
  }

  @override
  Future<bool> syncActiveClassIds(
    Set<String> activeClassIds, {
    bool clearPrevious = false,
  }) async {
    final data = await _readRaw();
    final classes = Map<String, dynamic>.from(data['classes'] as Map);
    if (clearPrevious) {
      classes.removeWhere((key, _) => !activeClassIds.contains(key));
    }
    for (final entry in classes.entries) {
      final schedule = entry.value;
      if (schedule is Map && schedule['classOffering'] is Map) {
        final offering =
            Map<String, dynamic>.from(schedule['classOffering'] as Map);
        offering['active'] = activeClassIds.contains(entry.key);
        schedule['classOffering'] = offering;
      }
    }
    data['classes'] = classes;
    await _writeRaw(data);
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async {
    final data = await _readRaw();
    final classes = Map<String, dynamic>.from(data['classes'] as Map);
    final list = <Map<String, dynamic>>[];
    for (final schedule in classes.values) {
      if (schedule is Map && schedule['classOffering'] is Map) {
        final offering =
            Map<String, dynamic>.from(schedule['classOffering'] as Map);
        if (offering['active'] != false) {
          list.add(offering);
        }
      }
    }
    return list;
  }

  @override
  Future<Map<String, dynamic>?> get(String classId) async {
    final data = await _readRaw();
    final classes = Map<String, dynamic>.from(data['classes'] as Map);
    final schedule = classes[classId];
    if (schedule is Map) {
      return Map<String, dynamic>.from(schedule);
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll() async {
    final data = await _readRaw();
    final classes = Map<String, dynamic>.from(data['classes'] as Map);
    final list = <Map<String, dynamic>>[];
    for (final schedule in classes.values) {
      if (schedule is Map) {
        final offering = schedule['classOffering'];
        if (offering is Map && offering['active'] != false) {
          list.add(Map<String, dynamic>.from(schedule));
        }
      }
    }
    return list;
  }
}
