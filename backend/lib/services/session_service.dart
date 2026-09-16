import '../repositories/sheets_repository.dart';

class AttendanceWindow {
  final String windowId;
  final String sessionId;
  final String classId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final bool isOpen;

  const AttendanceWindow({
    required this.windowId,
    required this.sessionId,
    required this.classId,
    required this.openedAt,
    required this.isOpen,
    this.closedAt,
  });

  Map<String, dynamic> toJson() => {
        'windowId': windowId,
        'sessionId': sessionId,
        'classId': classId,
        'status': isOpen ? 'open' : 'closed',
        'openedAt': openedAt.toUtc().toIso8601String(),
        if (closedAt != null) 'closedAt': closedAt!.toUtc().toIso8601String(),
      };
}

class SessionValidationException implements Exception {
  final String message;
  const SessionValidationException(this.message);

  @override
  String toString() => message;
}

class SessionStateException implements Exception {
  final String code;
  final String message;
  const SessionStateException(this.code, this.message);

  @override
  String toString() => message;
}

class SessionPersistenceException implements Exception {
  final String message;
  const SessionPersistenceException(this.message);

  @override
  String toString() => message;
}

/// Applies attendance-window lifecycle rules on top of the data gateway.
class SessionService {
  final SheetsRepository _repository;
  final Map<String, AttendanceWindow> _activeWindows = {};

  SessionService({SheetsRepository? repository})
      : _repository = repository ?? SheetsRepository();

  Future<AttendanceWindow> openSession({
    required String sessionId,
    required String classId,
  }) async {
    final normalizedSessionId = _required(sessionId, 'sessionId');
    final normalizedClassId = _required(classId, 'classId');
    final data = await _repository.openAttendanceWindow(normalizedSessionId);
    if (data == null) {
      throw const SessionPersistenceException(
        'Không thể mở phiên điểm danh trên kho dữ liệu.',
      );
    }
    final window = _windowFromGateway(
      data,
      sessionId: normalizedSessionId,
      classId: normalizedClassId,
    );
    _activeWindows[normalizedSessionId] = window;
    return window;
  }

  Future<AttendanceWindow> requireOpenSession({
    required String sessionId,
    required String classId,
  }) async {
    final normalizedSessionId = _required(sessionId, 'sessionId');
    final normalizedClassId = _required(classId, 'classId');

    // 1. Return immediately from in-memory cache if active and open
    final cached = _activeWindows[normalizedSessionId];
    if (cached != null) {
      if (cached.isOpen && cached.classId == normalizedClassId) {
        return cached;
      }
      throw const SessionStateException(
        'SESSION_CLOSED',
        'Phiên điểm danh đã đóng hoặc chưa được mở.',
      );
    }

    // 2. Fall back to remote gateway if not in cache (e.g. after server restart)
    final data = await _repository.getActiveWindow(normalizedSessionId);
    if (data == null || data['isOpen'] != true) {
      throw const SessionStateException(
        'SESSION_CLOSED',
        'Phiên điểm danh đã đóng hoặc chưa được mở.',
      );
    }
    final window = _windowFromGateway(
      data,
      sessionId: normalizedSessionId,
      classId: normalizedClassId,
    );
    _activeWindows[normalizedSessionId] = window;
    return window;
  }

  Future<AttendanceWindow> closeSession({
    required String sessionId,
    required String classId,
    required String windowId,
  }) async {
    final normalizedSessionId = _required(sessionId, 'sessionId');
    final normalizedClassId = _required(classId, 'classId');
    final normalizedWindowId = _required(windowId, 'windowId');

    // Check active window using cache first to avoid redundant remote GET
    final cached = _activeWindows[normalizedSessionId];
    final AttendanceWindow active;
    if (cached != null) {
      if (!cached.isOpen) {
        throw const SessionStateException(
          'SESSION_CLOSED',
          'Phiên điểm danh đã đóng hoặc chưa được mở.',
        );
      }
      active = cached;
    } else {
      active = await requireOpenSession(
        sessionId: normalizedSessionId,
        classId: normalizedClassId,
      );
    }

    if (active.windowId != normalizedWindowId) {
      throw const SessionStateException(
        'WINDOW_REPLACED',
        'Cửa sổ điểm danh này không còn là cửa sổ đang hoạt động.',
      );
    }

    final saved = await _repository.closeAttendanceWindow(normalizedWindowId);
    if (!saved) {
      throw const SessionPersistenceException(
        'Không thể xác nhận đóng phiên trên kho dữ liệu.',
      );
    }
    final closed = AttendanceWindow(
      windowId: active.windowId,
      sessionId: active.sessionId,
      classId: active.classId,
      openedAt: active.openedAt,
      closedAt: DateTime.now().toUtc(),
      isOpen: false,
    );
    _activeWindows[normalizedSessionId] = closed;
    return closed;
  }

  AttendanceWindow _windowFromGateway(
    Map<String, dynamic> data, {
    required String sessionId,
    required String classId,
  }) {
    final windowId = (data['windowId'] ?? data['id'])?.toString().trim() ?? '';
    final gatewaySessionId =
        (data['sessionId'] ?? data['lessonId'])?.toString().trim() ?? sessionId;
    final openedAt = DateTime.tryParse(data['openedAt']?.toString() ?? '');
    if (windowId.isEmpty || gatewaySessionId != sessionId || openedAt == null) {
      throw const SessionPersistenceException(
        'Kho dữ liệu trả về thông tin phiên không hợp lệ.',
      );
    }
    return AttendanceWindow(
      windowId: windowId,
      sessionId: sessionId,
      classId: classId,
      openedAt: openedAt.toUtc(),
      closedAt: DateTime.tryParse(data['closedAt']?.toString() ?? '')?.toUtc(),
      isOpen: data['isOpen'] == true,
    );
  }

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw SessionValidationException('$field không được để trống.');
    }
    return normalized;
  }
}
