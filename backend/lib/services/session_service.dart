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
    return _windowFromGateway(
      data,
      sessionId: normalizedSessionId,
      classId: normalizedClassId,
    );
  }

  Future<AttendanceWindow> requireOpenSession({
    required String sessionId,
    required String classId,
  }) async {
    final normalizedSessionId = _required(sessionId, 'sessionId');
    final normalizedClassId = _required(classId, 'classId');
    final data = await _repository.getActiveWindow(normalizedSessionId);
    if (data == null || data['isOpen'] != true) {
      throw const SessionStateException(
        'SESSION_CLOSED',
        'Phiên điểm danh đã đóng hoặc chưa được mở.',
      );
    }
    return _windowFromGateway(
      data,
      sessionId: normalizedSessionId,
      classId: normalizedClassId,
    );
  }

  Future<AttendanceWindow> closeSession({
    required String sessionId,
    required String classId,
    required String windowId,
  }) async {
    final active = await requireOpenSession(
      sessionId: sessionId,
      classId: classId,
    );
    final normalizedWindowId = _required(windowId, 'windowId');
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
    return AttendanceWindow(
      windowId: active.windowId,
      sessionId: active.sessionId,
      classId: active.classId,
      openedAt: active.openedAt,
      closedAt: DateTime.now().toUtc(),
      isOpen: false,
    );
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
