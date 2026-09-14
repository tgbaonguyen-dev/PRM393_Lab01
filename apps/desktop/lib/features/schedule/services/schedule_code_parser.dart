import '../models/schedule_models.dart';

class ScheduleCodeParser {
  /// Each lesson lasts 2 hours 15 minutes. Slots 1–2 and 3–4 are separated
  /// by 15 minutes, the afternoon/evening break is 30 minutes, then the
  /// 15-minute interval continues for slots 6–8.
  static const slotTimes = <int, (String, String)>{
    1: ('07:00', '09:15'),
    2: ('09:30', '11:45'),
    3: ('12:30', '14:45'),
    4: ('15:00', '17:15'),
    5: ('17:45', '20:00'),
    6: ('20:15', '22:30'),
    7: ('22:45', '01:00'),
    8: ('01:15', '03:30'),
  };

  static String? extractFromSheetName(String sheetName) {
    final match = RegExp(r'^([123][1-8])(?:_|$)').firstMatch(sheetName.trim());
    return match?.group(1);
  }

  static ScheduleRule? tryParse(String code) {
    if (!RegExp(r'^[123][1-8]$').hasMatch(code)) return null;

    final weekdayGroup = int.parse(code[0]);
    final dailySlot = int.parse(code[1]);
    final weekdays = switch (weekdayGroup) {
      1 => [DateTime.monday, DateTime.thursday],
      2 => [DateTime.tuesday, DateTime.friday],
      3 => [DateTime.wednesday, DateTime.saturday],
      _ => <int>[],
    };
    final times = slotTimes[dailySlot]!;
    return ScheduleRule(
      code: code,
      weekdays: weekdays,
      dailySlot: dailySlot,
      startTime: times.$1,
      endTime: times.$2,
    );
  }

  static ScheduleRule parse(String code) {
    final rule = tryParse(code);
    if (rule == null) {
      throw FormatException(
        'Mã lịch "$code" không hợp lệ. Mã phải từ 11 đến 38.',
      );
    }
    return rule;
  }
}
