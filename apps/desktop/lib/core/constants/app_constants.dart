/// Constants for the lecturer desktop application
class AppConstants {
  static const String appTitle = 'PRM393 Lecturer Attendance';
  static const String timeZone = 'Asia/Ho_Chi_Minh'; // UTC+7

  // Polling interval in seconds during active attendance window
  static const int pollIntervalSeconds = 5;

  // QR rotation interval in seconds
  static const int qrRotationSeconds = 15;

  // Daily teaching slot times (24h format)
  static const Map<int, (String, String)> dailySlots = {
    1: ('07:00', '09:15'),
    2: ('09:30', '11:45'),
    3: ('12:30', '14:45'),
    4: ('15:00', '17:15'),
  };
}
