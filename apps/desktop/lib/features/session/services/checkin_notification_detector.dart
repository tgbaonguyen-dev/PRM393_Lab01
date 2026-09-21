import '../widgets/checkin_notification_toast.dart';

/// Bộ phát hiện các sự kiện sinh viên vừa điểm danh thành công
class CheckinNotificationDetector {
  final Map<String, String> _lastKnownStatuses = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Nạp trạng thái ban đầu (không kích hoạt thông báo cho dữ liệu lịch sử)
  void initialize(Map<String, String> initialStatuses) {
    _lastKnownStatuses.clear();
    for (final entry in initialStatuses.entries) {
      _lastKnownStatuses[entry.key.trim().toLowerCase()] = entry.value.trim().toUpperCase();
    }
    _isInitialized = true;
  }

  /// Đối chiếu trạng thái mới với trạng thái trước đó để phát hiện sinh viên vừa có mặt (P)
  List<CheckinNotificationItem> processNewStatuses({
    required Map<String, String> newStatuses,
    required List<Map<String, dynamic>> roster,
    DateTime? now,
  }) {
    if (!_isInitialized) {
      initialize(newStatuses);
      return const [];
    }

    final timestamp = now ?? DateTime.now();
    final newEvents = <CheckinNotificationItem>[];

    // Tạo bản đồ tra cứu nhanh sinh viên trong roster
    final rosterByEmail = <String, Map<String, dynamic>>{};
    for (final student in roster) {
      final email = (student['studentEmail'] ?? student['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        rosterByEmail[email] = student;
      }
    }

    for (final entry in newStatuses.entries) {
      final email = entry.key.trim().toLowerCase();
      final status = entry.value.trim().toUpperCase();
      final previous = _lastKnownStatuses[email] ?? 'A';

      // Điều kiện kích hoạt thông báo: từ chưa có mặt -> chuyển sang 'P'
      if (status == 'P' && previous != 'P') {
        final student = rosterByEmail[email];
        final fullName = (student?['fullName'] ?? student?['name'] ?? email).toString();
        final rollNumber = (student?['rollNumber'] ?? student?['roll'] ?? '').toString();

        newEvents.add(
          CheckinNotificationItem(
            id: '$email-${timestamp.millisecondsSinceEpoch}',
            fullName: fullName,
            rollNumber: rollNumber,
            email: email,
            timestamp: timestamp,
          ),
        );
      }

      _lastKnownStatuses[email] = status;
    }

    return newEvents;
  }

  /// Cập nhật thủ công trạng thái của 1 sinh viên (tránh phát thông báo khi giảng viên tự bấm)
  void updateStatus(String email, String status) {
    _lastKnownStatuses[email.trim().toLowerCase()] = status.trim().toUpperCase();
  }

  void reset() {
    _lastKnownStatuses.clear();
    _isInitialized = false;
  }
}
