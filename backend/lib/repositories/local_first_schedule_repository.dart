import 'dart:async';
import 'dart:io';

import '../services/schedule_service.dart';
import 'sheets_repository.dart';

/// Repository kết hợp: Lưu dữ liệu vào file JSON local trước (bảo đảm an toàn dữ liệu,
/// phản hồi tức thì < 10ms, hỗ trợ Offline), sau đó đồng bộ lên Google Sheets (tạo Sheet Overview
/// và Sheet riêng cho từng lớp học).
class LocalFirstScheduleRepository implements ScheduleRepository {
  final ScheduleRepository local;
  final SheetsRepository? sheetsGateway;

  LocalFirstScheduleRepository({
    required this.local,
    this.sheetsGateway,
  });

  @override
  Future<bool> save({
    required Map<String, dynamic> classOffering,
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> lessons,
  }) async {
    // 1. Luôn lưu vào JSON local trước
    final localSaved = await local.save(
      classOffering: classOffering,
      students: students,
      lessons: lessons,
    );

    // 2. Đồng bộ TOÀN BỘ các lớp lên Google Sheets (nếu có cấu hình gateway)
    if (sheetsGateway != null) {
      final allActive = await local.getAll();
      _syncToSheetsSafely(allActive.isNotEmpty
          ? allActive
          : [
              {
                'classOffering': classOffering,
                'students': students,
                'lessons': lessons,
              }
            ]);
    }

    return localSaved;
  }

  @override
  Future<bool> saveAll(List<Map<String, dynamic>> schedules) async {
    // 1. Luôn lưu vào JSON local trước
    final localSaved = await local.saveAll(schedules);

    // 2. Đồng bộ TOÀN BỘ các lớp active lên Google Sheets (tạo Sheet Overview và đầy đủ Sheet từng lớp)
    if (sheetsGateway != null) {
      final allActive = await local.getAll();
      if (allActive.isNotEmpty) {
        _syncToSheetsSafely(allActive);
      } else if (schedules.isNotEmpty) {
        _syncToSheetsSafely(schedules);
      }
    }

    return localSaved;
  }

  @override
  Future<bool> syncActiveClassIds(Set<String> activeClassIds) async {
    final synced = await local.syncActiveClassIds(activeClassIds);

    // Khi cập nhật danh sách lớp active, luôn đồng bộ lại toàn bộ các lớp active lên Google Sheets
    // Giúp khôi phục lại bất kỳ sheet nào bị xoá trên Google Drive
    if (sheetsGateway != null) {
      final allActive = await local.getAll();
      if (allActive.isNotEmpty) {
        _syncToSheetsSafely(allActive);
      }
    }

    return synced;
  }

  @override
  Future<List<Map<String, dynamic>>> list() async {
    // Đọc từ JSON local trước để phản hồi ngay lập tức
    final localList = await local.list();
    if (localList.isNotEmpty) {
      return localList;
    }
    // Nếu local rỗng, thử kéo từ sheetsGateway (nếu trước đó đã lưu trên Sheets)
    if (sheetsGateway != null) {
      try {
        final remote = await SheetsScheduleRepository(sheetsGateway).getAll();
        if (remote.isNotEmpty) {
          await local.saveAll(remote);
          return await local.list();
        }
      } catch (err) {
        stderr.writeln('[LocalFirstScheduleRepository] Fallback to remote failed: $err');
      }
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>?> get(String classId) async {
    final cached = await local.get(classId);
    if (cached != null) {
      return cached;
    }
    if (sheetsGateway != null) {
      try {
        final remote = await SheetsScheduleRepository(sheetsGateway).get(classId);
        if (remote != null) {
          final offering = remote['classOffering'];
          final students = (remote['students'] as List? ?? []).cast<Map<String, dynamic>>();
          final lessons = (remote['lessons'] as List? ?? []).cast<Map<String, dynamic>>();
          if (offering is Map) {
            await local.save(
              classOffering: Map<String, dynamic>.from(offering),
              students: students,
              lessons: lessons,
            );
          }
          return remote;
        }
      } catch (err) {
        stderr.writeln('[LocalFirstScheduleRepository] Fallback get failed: $err');
      }
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll() async {
    // Đọc ngay từ JSON local
    final localAll = await local.getAll();
    if (localAll.isNotEmpty) {
      return localAll;
    }
    // Nếu local rỗng, thử kéo từ sheetsGateway
    if (sheetsGateway != null) {
      try {
        final remote = await SheetsScheduleRepository(sheetsGateway).getAll();
        if (remote.isNotEmpty) {
          await local.saveAll(remote);
          return await local.getAll();
        }
      } catch (err) {
        stderr.writeln('[LocalFirstScheduleRepository] Fallback getAll failed: $err');
      }
    }
    return const [];
  }

  Timer? _syncDebounceTimer;
  bool _isSyncing = false;
  List<Map<String, dynamic>>? _queuedSyncPayload;

  /// Đồng bộ danh sách lớp lên Google Sheets an toàn (có debounce và queue tránh conflict gọi đồng thời)
  void _syncToSheetsSafely(List<Map<String, dynamic>> schedules) {
    if (sheetsGateway == null || schedules.isEmpty) return;

    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _executeSync(schedules);
    });
  }

  void _executeSync(List<Map<String, dynamic>> schedules) async {
    if (_isSyncing) {
      _queuedSyncPayload = schedules;
      return;
    }
    _isSyncing = true;
    try {
      final classesPayload = schedules.map((item) {
        final offering = Map<String, dynamic>.from(
          item['classOffering'] ?? item['offering'] ?? {},
        );
        final roster = (item['students'] ?? item['roster'] as List? ?? [])
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
        final lessons = (item['lessons'] as List? ?? [])
            .whereType<Map>()
            .map((l) => Map<String, dynamic>.from(l))
            .toList();

        return {
          'className': offering['classCode'] ?? offering['className'] ?? '',
          'subjectCode': offering['subjectCode'] ?? 'PRM393',
          'scheduleCode': offering['scheduleCode']?.toString() ?? '12',
          'slotCount': offering['lessonCount'] ?? 20,
          'roster': roster,
          'lessons': lessons,
        };
      }).toList();

      // Lấy ngày bắt đầu từ buổi học đầu tiên
      String startDateStr = DateTime.now().toIso8601String().split('T').first;
      for (final item in schedules) {
        final lessons = item['lessons'] as List?;
        if (lessons != null && lessons.isNotEmpty) {
          final firstDate = lessons.first['date']?.toString();
          if (firstDate != null && firstDate.isNotEmpty) {
            startDateStr = firstDate.split('T').first;
            break;
          }
        }
      }

      // Gọi đồng bộ lên Google Sheets (tạo tab Overview và các sheet từng lớp)
      await sheetsGateway!.syncAllClasses(
        classes: classesPayload,
        startDate: startDateStr,
      );
    } catch (err) {
      stderr.writeln('[LocalFirstScheduleRepository] Google Sheets sync warning: $err');
    } finally {
      _isSyncing = false;
      if (_queuedSyncPayload != null) {
        final next = _queuedSyncPayload!;
        _queuedSyncPayload = null;
        _executeSync(next);
      }
    }
  }
}
