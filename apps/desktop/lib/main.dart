import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

import 'core/constants/app_constants.dart';
import 'features/markbook_import/models/markbook_data.dart';
import 'features/markbook_import/services/markbook_parser.dart';
import 'features/schedule/services/schedule_generator.dart';
import 'features/schedule/models/lesson_schedule.dart';
import 'features/attendance/models/attendance_state.dart';
import 'features/attendance/services/attendance_storage_service.dart';
import 'features/export/services/export_service.dart';
import 'core/network/api_client.dart';

void main() {
  runApp(const LecturerAttendanceApp());
}

class LecturerAttendanceApp extends StatelessWidget {
  const LecturerAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50: clean, easy on the eyes
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        fontFamily: 'Segoe UI',
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;

  // Global State
  List<ParsedSheetResult> _parsedSheets = [];
  ParsedSheetResult? _selectedSheet;
  int _configuredSlotCount = 20;
  DateTime _firstLessonDate = DateTime(2026, 9, 7); // Default to Monday
  List<LessonSchedule> _generatedLessons = [];
  LessonSchedule? _activeLesson;

  // FAP Timetable View State
  bool _isFapWeeklyView = true;
  DateTime _currentWeekMonday = DateTime(2026, 9, 7);
  bool _showAllClasses = true;
  final Map<String, List<LessonSchedule>> _allSheetLessons = {};

  // Active Attendance Window State
  bool _isWindowOpen = false;
  String _currentQrToken = '';
  int _secondsRemaining = 15;
  Timer? _qrTimer;
  Timer? _pollTimer;

  // Persistent Attendance Matrix: sheetName -> (slotSequence -> (email -> LiveStudentAttendance))
  final Map<String, Map<int, Map<String, LiveStudentAttendance>>> _attendanceStore = {};

  // Export View State
  ParsedSheetResult? _exportSelectedSheet;
  final Set<int> _exportSelectedSlots = {};

  // Search filter states for comfortable UI
  String _importSearchQuery = '';
  String _liveSearchQuery = '';

  final MarkbookParser _parser = MarkbookParser();
  final ExportService _exportService = ExportService();
  final AttendanceStorageService _storageService = AttendanceStorageService();
  final ApiClient _apiClient = ApiClient(baseUrl: 'http://localhost:8080');
  bool _isSyncing = false;
  String? _currentWindowId;
  String? _googleSheetUrl;

  Future<void> _openGoogleSheetInBrowser() async {
    if (_googleSheetUrl == null || _googleSheetUrl!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Bạn chưa đồng bộ lên Google Sheet! Hãy bấm "Mở FA26_Markbook.ods" hoặc "Đồng bộ đám mây" rồi chọn "Xác nhận & Đồng bộ" trước nhé.'),
            backgroundColor: Color(0xFFD97706),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    final url = _googleSheetUrl!;
    try {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } catch (_) {
      try {
        await Process.run('explorer', [url]);
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPersistedData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sampleFile = _findSampleFile();
      if (sampleFile != null && _parsedSheets.isEmpty) {
        _processFilePath(sampleFile.path, autoSync: false);
      }
    });
  }

  File? _findSampleFile() {
    var dir = Directory.current;
    for (int i = 0; i < 6; i++) {
      final target = File('${dir.path}/sample_data/FA26_Markbook.ods');
      if (target.existsSync()) return target;
      final targetBackslash = File('${dir.path}\\sample_data\\FA26_Markbook.ods');
      if (targetBackslash.existsSync()) return targetBackslash;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    const candidates = [
      'sample_data/FA26_Markbook.ods',
      '../sample_data/FA26_Markbook.ods',
      '../../sample_data/FA26_Markbook.ods',
      '../../../sample_data/FA26_Markbook.ods',
      '../../../../sample_data/FA26_Markbook.ods',
      '../../../../../sample_data/FA26_Markbook.ods',
      r'D:\Github\Repositories\PRM393\PRM393_Lab01\sample_data\FA26_Markbook.ods',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }
    return null;
  }

  Future<void> _loadPersistedData() async {
    final persisted = await _storageService.loadStore();
    if (persisted.isNotEmpty && mounted) {
      setState(() {
        _attendanceStore.addAll(persisted);
      });
    }
  }

  void _saveStoreToDisk() {
    _storageService.saveStore(_attendanceStore);
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  // Helper methods for multi-slot attendance persistence
  Map<String, LiveStudentAttendance> _getSlotAttendance(
    String sheetName,
    int slotSequence, {
    List<RosterStudent>? roster,
  }) {
    final sheetStore = _attendanceStore.putIfAbsent(sheetName, () => {});
    if (!sheetStore.containsKey(slotSequence)) {
      final slotMap = <String, LiveStudentAttendance>{};
      final studentList = roster ??
          (_parsedSheets.where((s) => s.sheetName == sheetName).firstOrNull?.roster ?? []);
      for (final student in studentList) {
        slotMap[student.email.toLowerCase()] = LiveStudentAttendance(
          studentEmail: student.email,
          studentName: student.fullName,
          rollNumber: student.rollNumber,
          status: AttendanceStatus.blank,
        );
      }
      sheetStore[slotSequence] = slotMap;
    }
    return sheetStore[slotSequence]!;
  }

  bool _isSlotAttended(String sheetName, int slotSequence) {
    final records = _attendanceStore[sheetName]?[slotSequence];
    if (records == null || records.isEmpty) return false;
    return records.values.any((s) => s.status != AttendanceStatus.blank);
  }

  void _selectAllExportSlots(ParsedSheetResult sheet) {
    _exportSelectedSlots.clear();
    for (int i = 1; i <= sheet.detectedSlotCount; i++) {
      _exportSelectedSlots.add(i);
    }
  }

  void _selectAttendedExportSlots(ParsedSheetResult sheet) {
    _exportSelectedSlots.clear();
    for (int i = 1; i <= sheet.detectedSlotCount; i++) {
      if (_isSlotAttended(sheet.sheetName, i)) {
        _exportSelectedSlots.add(i);
      }
    }
  }

  // --- Markbook Import logic ---
  Future<void> _pickAndParseFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ods', 'xlsx'],
    );

    if (result != null && result.files.single.path != null) {
      await _promptStartDateAndProcess(result.files.single.path!);
    }
  }

  Future<void> _loadSampleFile() async {
    final sampleFile = _findSampleFile();
    if (sampleFile != null && sampleFile.existsSync()) {
      await _promptStartDateAndProcess(sampleFile.path);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy tệp mẫu sample_data/FA26_Markbook.ods')),
      );
    }
  }

  /// Popup cho Giảng viên chọn ngày bắt đầu của lịch trước khi Import
  Future<void> _promptStartDateAndProcess(String filePath) async {
    DateTime chosenDate = _firstLessonDate;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateStr = DateFormat('EEEE, dd/MM/yyyy').format(chosenDate);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: Color(0xFF2563EB), size: 24),
                  SizedBox(width: 10),
                  Text('Chọn Ngày Bắt Đầu Học Kỳ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chọn ngày bắt đầu của buổi học đầu tiên trong kỳ. Hệ thống sẽ tự động tính lịch 20 buổi học và tạo các bảng điểm danh trên Google Sheet theo ngày này:',
                      style: TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Ngày bắt đầu kỳ học:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              const SizedBox(height: 2),
                              Text(
                                dateStr,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1D4ED8)),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: chosenDate,
                                firstDate: DateTime(2025, 1, 1),
                                lastDate: DateTime(2030, 12, 31),
                              );
                              if (picked != null) {
                                setDialogState(() => chosenDate = picked);
                              }
                            },
                            icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                            label: const Text('Đổi ngày...'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1D4ED8),
                              elevation: 0,
                              side: const BorderSide(color: Color(0xFFBFDBFE)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Quy chế FAP: Sinh viên được nghỉ <= 20% tổng số slot. Quá 20% (> 4 slot) sẽ bị CẤM THI.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: const Text('Xác nhận & Đồng bộ Google Sheet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      setState(() => _firstLessonDate = chosenDate);
      await _processFilePath(filePath, autoSync: true);
    }
  }

  Future<void> _processFilePath(String path, {bool autoSync = true}) async {
    try {
      final sheets = await _parser.parseFile(File(path));
      if (!mounted) return;
      setState(() {
        _parsedSheets = sheets;
        if (sheets.isNotEmpty) {
          _selectSheet(sheets.first);
          _exportSelectedSheet = sheets.first;
          _selectAllExportSlots(sheets.first);
        }
        _generateAllLessons();
      });

      if (autoSync) {
        // Tự động tạo và đồng bộ toàn bộ các bảng tính lên Google Sheet
        _syncAllImportedSheetsToCloud(showFeedback: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi đọc tệp: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _selectSheet(ParsedSheetResult sheet) {
    setState(() {
      _selectedSheet = sheet;
      _configuredSlotCount = sheet.detectedSlotCount;
      _generateLessonsForSheet();
      _generateAllLessons();
      if (_exportSelectedSheet == null) {
        _exportSelectedSheet = sheet;
        _selectAllExportSlots(sheet);
      }
    });
  }

  // --- Schedule logic ---
  void _generateAllLessons() {
    _allSheetLessons.clear();
    for (final sheet in _parsedSheets) {
      try {
        final lessons = ScheduleGenerator.generateLessons(
          scheduleCode: sheet.scheduleCode,
          firstDate: _firstLessonDate,
          slotCount: sheet.detectedSlotCount,
        );
        _allSheetLessons[sheet.sheetName] = lessons;
      } catch (_) {
        final validWeekdays = ScheduleGenerator.getWeekdaysForScheduleCode(sheet.scheduleCode);
        var corrected = _firstLessonDate;
        while (!validWeekdays.contains(corrected.weekday)) {
          corrected = corrected.add(const Duration(days: 1));
        }
        final lessons = ScheduleGenerator.generateLessons(
          scheduleCode: sheet.scheduleCode,
          firstDate: corrected,
          slotCount: sheet.detectedSlotCount,
        );
        _allSheetLessons[sheet.sheetName] = lessons;
      }
    }
  }

  void _generateLessonsForSheet() {
    if (_selectedSheet == null) return;
    try {
      final lessons = ScheduleGenerator.generateLessons(
        scheduleCode: _selectedSheet!.scheduleCode,
        firstDate: _firstLessonDate,
        slotCount: _configuredSlotCount,
      );
      setState(() {
        _generatedLessons = lessons;
        if (_activeLesson == null || !_generatedLessons.any((l) => l.sequenceNumber == _activeLesson!.sequenceNumber)) {
          _activeLesson = lessons.isNotEmpty ? lessons.first : null;
        }
        if (_activeLesson != null) {
          _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster);
        }
      });
    } catch (_) {
      final validWeekdays = ScheduleGenerator.getWeekdaysForScheduleCode(_selectedSheet!.scheduleCode);
      var corrected = _firstLessonDate;
      while (!validWeekdays.contains(corrected.weekday)) {
        corrected = corrected.add(const Duration(days: 1));
      }
      _firstLessonDate = corrected;
      final lessons = ScheduleGenerator.generateLessons(
        scheduleCode: _selectedSheet!.scheduleCode,
        firstDate: _firstLessonDate,
        slotCount: _configuredSlotCount,
      );
      setState(() {
        _generatedLessons = lessons;
        if (_activeLesson == null || !_generatedLessons.any((l) => l.sequenceNumber == _activeLesson!.sequenceNumber)) {
          _activeLesson = lessons.isNotEmpty ? lessons.first : null;
        }
        if (_activeLesson != null) {
          _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster);
        }
      });
    }
  }

  // --- Attendance Window & Dynamic QR logic ---
  void _toggleAttendanceWindow() {
    if (_isWindowOpen) {
      _closeAttendanceWindow();
    } else {
      _openAttendanceWindow();
    }
  }

  /// Synchronizes the active class, roster, and lessons to Google Sheets via Next.js
  /// Synchronizes all classes, Overview, and per-class sheets to Google Sheets
  Future<bool> _syncToCloud({bool showFeedback = true}) async {
    await _syncAllImportedSheetsToCloud(showFeedback: showFeedback);
    return true;
  }

  /// Tự động tạo Overview và các sheet từng lớp học từ tệp Markbook lên Google Sheet
  Future<void> _syncAllImportedSheetsToCloud({bool showFeedback = true}) async {
    if (_parsedSheets.isEmpty) return;
    setState(() => _isSyncing = true);

    try {
      final startDateStr = _firstLessonDate.toIso8601String().split('T')[0];
      final classesPayload = _parsedSheets.map((sheet) {
        final semester = 'FA26';
        final sheetLessons = _allSheetLessons[sheet.sheetName] ?? [];
        final lessons = sheetLessons.map((l) => {
          'id': '${sheet.subjectCode}_${sheet.className}_Lesson_${l.sequenceNumber}',
          'sequenceNumber': l.sequenceNumber,
          'date': l.date.toIso8601String().split('T')[0],
          'dailySlot': l.dailySlot,
          'startTime': l.startTime,
          'endTime': l.endTime,
          'status': l.sequenceNumber == 1 ? 'completed' : 'scheduled',
        }).toList();

        return {
          'id': '${sheet.subjectCode}_${sheet.className}_$semester',
          'className': sheet.className,
          'subjectCode': sheet.subjectCode,
          'semester': semester,
          'scheduleCode': sheet.scheduleCode,
          'slotCount': sheet.detectedSlotCount,
          'roster': sheet.roster.map((s) {
            final studentAttendance = <String, String>{};
            for (int slotNum = 1; slotNum <= sheet.detectedSlotCount; slotNum++) {
              final record = _attendanceStore[sheet.sheetName]?[slotNum]?[s.email.toLowerCase()];
              if (record != null && record.status != AttendanceStatus.blank) {
                studentAttendance['$slotNum'] = record.status == AttendanceStatus.present ? 'P' : 'A';
              }
            }
            return {
              'rollNumber': s.rollNumber,
              'fullName': s.fullName,
              'email': s.email,
              'memberCode': s.memberCode,
              'attendance': studentAttendance,
            };
          }).toList(),
          'lessons': lessons,
        };
      }).toList();

      final res = await _apiClient.syncAllClasses(
        classes: classesPayload,
        startDate: startDateStr,
      );

      final isSuccess = res != null && res['success'] == true;
      if (res != null && res['spreadsheetUrl'] != null) {
        _googleSheetUrl = res['spreadsheetUrl'] as String?;
      }

      if (mounted) {
        setState(() => _isSyncing = false);
        if (showFeedback) {
          if (isSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('☁️ Đã tạo Overview và đồng bộ ${_parsedSheets.length} lớp học lên Google Sheet thành công!'),
                backgroundColor: const Color(0xFF059669),
                duration: const Duration(seconds: 6),
                action: _googleSheetUrl != null
                    ? SnackBarAction(
                        label: 'Mở Google Sheet',
                        textColor: Colors.white,
                        onPressed: _openGoogleSheetInBrowser,
                      )
                    : null,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('⚠️ Đồng bộ thất bại: Google Apps Script chưa nhận được phiên bản mới hoặc lỗi kết nối.'),
                backgroundColor: const Color(0xFFDC2626),
                duration: const Duration(seconds: 8),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi đồng bộ: $e'), backgroundColor: const Color(0xFFDC2626)),
          );
        }
      }
    }
  }

  Future<void> _openAttendanceWindow() async {
    if (_selectedSheet == null || _activeLesson == null) return;

    final lessonId = '${_selectedSheet!.subjectCode}_${_selectedSheet!.className}_Lesson_${_activeLesson!.sequenceNumber}';

    // Open window on backend and initialize slot on sheet without recreating database
    final windowRes = await _apiClient.openWindow(lessonId);
    if (windowRes != null && windowRes['window'] != null) {
      _currentWindowId = windowRes['window']['id'] as String?;
    } else {
      _currentWindowId = 'win_${DateTime.now().millisecondsSinceEpoch}';
    }

    setState(() {
      _isWindowOpen = true;
      _secondsRemaining = 15;

      final slotMap = _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster);
      // On first open: blank becomes absent 'A' (FR-09)
      slotMap.forEach((email, student) {
        if (student.status == AttendanceStatus.blank) {
          slotMap[email] = LiveStudentAttendance(
            studentEmail: student.studentEmail,
            studentName: student.studentName,
            rollNumber: student.rollNumber,
            status: AttendanceStatus.absent,
            isManualOverride: student.isManualOverride,
          );
        }
      });

      _rotateQrToken();
    });

    _saveStoreToDisk();

    // Start 15-second QR rotation timer
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() {
          _secondsRemaining = 15;
          _rotateQrToken();
        });
      }
    });

    // Start 5-second polling timer (FR-11)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final res = await _apiClient.pollAttendance(lessonId);
      if (res != null && res['results'] != null) {
        final results = res['results'] as List;
        bool changed = false;
        final slotMap = _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster);
        for (final r in results) {
          final email = (r['studentEmail'] as String? ?? '').toLowerCase();
          final status = r['status'] as String? ?? '';
          if (email.isNotEmpty && status == 'P') {
            final current = slotMap[email];
            if (current != null && current.status != AttendanceStatus.present) {
              slotMap[email] = LiveStudentAttendance(
                studentEmail: current.studentEmail,
                studentName: current.studentName,
                rollNumber: current.rollNumber,
                status: AttendanceStatus.present,
                isManualOverride: current.isManualOverride,
              );
              changed = true;
            }
          }
        }
        if (changed && mounted) {
          setState(() {});
          _saveStoreToDisk();
        }
      }
    });
  }

  void _closeAttendanceWindow() {
    _qrTimer?.cancel();
    _pollTimer?.cancel();
    if (_currentWindowId != null) {
      _apiClient.closeWindow(_currentWindowId!);
    }
    setState(() {
      _isWindowOpen = false;
      _currentQrToken = '';
    });
    _saveStoreToDisk();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã đóng ca điểm danh thành công.')),
    );
  }

  Future<void> _rotateQrToken() async {
    final lessonId = '${_selectedSheet?.subjectCode}_${_selectedSheet?.className}_Lesson_${_activeLesson?.sequenceNumber ?? 1}';
    final windowId = _currentWindowId ?? 'win_${DateTime.now().millisecondsSinceEpoch}';

    final res = await _apiClient.generateQrToken(windowId, lessonId);
    if (res != null && res['token'] != null) {
      if (mounted) {
        setState(() {
          _currentQrToken = 'http://localhost:3000/checkin?token=${res['token']}';
        });
      }
    } else {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final token = 'prm393_${_selectedSheet?.className}_lesson${_activeLesson?.sequenceNumber ?? 1}_$timestamp';
      if (mounted) {
        setState(() {
          _currentQrToken = 'http://localhost:3000/checkin?token=$token';
        });
      }
    }
  }

  // Manual Override (FR-14)
  void _toggleStudentAttendance(String email) {
    if (_selectedSheet == null || _activeLesson == null) return;
    final slotMap = _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster);
    final student = slotMap[email.toLowerCase()];
    if (student == null) return;

    final newStatus = student.status == AttendanceStatus.present
        ? AttendanceStatus.absent
        : AttendanceStatus.present;

    setState(() {
      slotMap[email.toLowerCase()] = LiveStudentAttendance(
        studentEmail: student.studentEmail,
        studentName: student.studentName,
        rollNumber: student.rollNumber,
        status: newStatus,
        isManualOverride: false,
        checkedInAt: DateTime.now(),
      );
    });

    _saveStoreToDisk();

    // Cập nhật Realtime trực tiếp vào ô tương ứng trên Google Sheet
    final lessonId = '${_selectedSheet!.subjectCode}_${_selectedSheet!.className}_Lesson_${_activeLesson!.sequenceNumber}';
    final statusStr = newStatus == AttendanceStatus.present ? 'P' : 'A';
    _apiClient.manualOverride(
      lessonId: lessonId,
      studentEmail: email,
      status: statusStr,
    ).then((ok) {
      debugPrint('[Desktop Override] $lessonId - $email: $statusStr -> ${ok ? "Thành công" : "Thất bại"}');
    }).catchError((err) {
      debugPrint('[Desktop Override Error] $err');
    });
  }

  // Simulate a student scanning QR
  void _simulateStudentCheckIn(String email) {
    if (_selectedSheet == null || _activeLesson == null) return;
    final slotMap = _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster);
    final student = slotMap[email.toLowerCase()];
    if (student == null) return;

    setState(() {
      slotMap[email.toLowerCase()] = LiveStudentAttendance(
        studentEmail: student.studentEmail,
        studentName: student.studentName,
        rollNumber: student.rollNumber,
        status: AttendanceStatus.present,
        isManualOverride: false,
        checkedInAt: DateTime.now(),
      );
    });

    _saveStoreToDisk();

    // Cập nhật Realtime trực tiếp lên Google Sheet
    final lessonId = '${_selectedSheet!.subjectCode}_${_selectedSheet!.className}_Lesson_${_activeLesson!.sequenceNumber}';
    _apiClient.manualOverride(
      lessonId: lessonId,
      studentEmail: email,
      status: 'P',
    ).then((ok) {
      debugPrint('[Desktop CheckIn] $lessonId - $email: P -> ${ok ? "Thành công" : "Thất bại"}');
    }).catchError((err) {
      debugPrint('[Desktop CheckIn Error] $err');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Modern Desktop Sidebar
          Container(
            width: 240,
            color: const Color(0xFF0F172A), // Deep Slate 900
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PRM393',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Attendance Portal',
                                style: TextStyle(
                                  color: Color(0xFF93C5FD),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF1E293B)),
                const SizedBox(height: 14),

                // Navigation Items
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      _buildSidebarNavItem(
                        index: 0,
                        icon: Icons.upload_file_rounded,
                        title: 'Nhập Bảng điểm',
                        subtitle: 'File .ods / .xlsx',
                      ),
                      const SizedBox(height: 6),
                      _buildSidebarNavItem(
                        index: 1,
                        icon: Icons.calendar_view_week_rounded,
                        title: 'Lịch Giảng dạy',
                        subtitle: 'Thời khóa biểu FAP',
                      ),
                      const SizedBox(height: 6),
                      _buildSidebarNavItem(
                        index: 2,
                        icon: Icons.qr_code_2_rounded,
                        title: 'Điểm danh Live',
                        subtitle: 'Chiếu QR & Sĩ số',
                      ),
                      const SizedBox(height: 6),
                      _buildSidebarNavItem(
                        index: 3,
                        icon: Icons.file_download_rounded,
                        title: 'Xuất Báo cáo',
                        subtitle: 'Xuất Excel & CSV',
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Nút Mở Google Sheet trên Drive
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: InkWell(
                    onTap: _openGoogleSheetInBrowser,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.6)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.table_chart_rounded, color: Color(0xFF2DD4BF), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Google Sheet', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                SizedBox(height: 2),
                                Text('Mở trên Drive ↗', style: TextStyle(color: Color(0xFF99F6E4), fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Bottom Persistence & Semester Status Card
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Lưu trữ cục bộ: Đang bật',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Học kỳ: FA26 (Kỳ Fall 2026)',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: _buildCurrentView(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF64748B),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_selectedIndex) {
      case 0:
        return _buildMarkbookImportView();
      case 1:
        return _buildScheduleSetupView();
      case 2:
        return _buildLiveAttendanceView();
      case 3:
        return _buildExportView();
      default:
        return const SizedBox();
    }
  }

  // --- View 1: Markbook Import ---
  Widget _buildMarkbookImportView() {
    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nhập Bảng điểm Giảng viên', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Hỗ trợ định dạng .ods và .xlsx có nhiều bảng tính (Worksheets)', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  if (_parsedSheets.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: _isSyncing ? null : () => _syncAllImportedSheetsToCloud(showFeedback: true),
                      icon: _isSyncing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_outlined, color: Color(0xFF1D4ED8)),
                      label: Text(_isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ lên Google Sheet'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1D4ED8),
                        side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _openGoogleSheetInBrowser,
                    icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF0F766E), size: 18),
                    label: const Text('Mở file trên Drive'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFF0FDFA),
                      foregroundColor: const Color(0xFF0F766E),
                      side: const BorderSide(color: Color(0xFF99F6E4), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _loadSampleFile,
                    icon: const Icon(Icons.file_present_rounded, color: Color(0xFF2563EB)),
                    label: const Text('Mở FA26_Markbook.ods mẫu'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E293B),
                      side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _pickAndParseFile,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Chọn Tệp từ máy tính'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      elevation: 2,
                      shadowColor: const Color(0xFF2563EB).withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_parsedSheets.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.description_outlined, size: 56, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Chưa có bảng tính nào được tải lên', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                    const SizedBox(height: 8),
                    const Text('Hãy chọn tệp từ máy hoặc nhấn "Mở FA26_Markbook.ods mẫu" để kiểm tra.', style: TextStyle(color: Color(0xFF64748B))),
                  ],
                ),
              ),
            )
          else ...[
            Text('Các lớp được phát hiện (${_parsedSheets.length} lớp học):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
            const SizedBox(height: 12),
            SizedBox(
              height: 135,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _parsedSheets.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final s = _parsedSheets[index];
                  final isSelected = _selectedSheet == s;
                  return InkWell(
                    onTap: () => _selectSheet(s),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 250,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected ? const Color(0xFF2563EB).withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.02),
                            blurRadius: isSelected ? 8 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(s.subjectCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                ),
                                child: Text('Mã: ${s.scheduleCode}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4338CA))),
                              ),
                            ],
                          ),
                          Text('Lớp: ${s.className}', style: const TextStyle(color: Color(0xFF475569), fontSize: 13, fontWeight: FontWeight.w600)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFF2563EB)),
                                  const SizedBox(width: 4),
                                  Text('${s.roster.length} sinh viên', style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              Text('${s.detectedSlotCount} buổi', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            if (_selectedSheet != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Danh sách sinh viên: ${_selectedSheet!.className}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${_selectedSheet!.roster.length} sinh viên', style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 240,
                        height: 38,
                        child: TextField(
                          onChanged: (val) => setState(() => _importSearchQuery = val),
                          decoration: InputDecoration(
                            hintText: 'Tìm kiếm tên, MSSV...',
                            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _selectedIndex = 1),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text('Tiếp tục: Xem Lịch Giảng dạy'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final filteredRoster = _selectedSheet!.roster.where((st) {
                      if (_importSearchQuery.isEmpty) return true;
                      final q = _importSearchQuery.toLowerCase();
                      return st.fullName.toLowerCase().contains(q) ||
                          st.rollNumber.toLowerCase().contains(q) ||
                          st.email.toLowerCase().contains(q);
                    }).toList();

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: filteredRoster.isEmpty
                          ? const Center(
                              child: Text('Không tìm thấy sinh viên phù hợp.', style: TextStyle(color: Color(0xFF64748B))),
                            )
                          : ListView.separated(
                              itemCount: filteredRoster.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (context, idx) {
                                final student = filteredRoster[idx];
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: const Color(0xFF334155),
                                    child: Text('${idx + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(student.fullName, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                  subtitle: Text(student.email, style: const TextStyle(color: Color(0xFF64748B))),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(student.rollNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                  ),
                                );
                              },
                            ),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // --- View 2: Schedule Setup & FAP Timetable ---
  Widget _buildScheduleSetupView() {
    if (_selectedSheet == null) {
      return const Center(child: Text('Vui lòng chọn hoặc nhập bảng điểm ở Bước 1 trước.'));
    }

    final weekEnd = _currentWeekMonday.add(const Duration(days: 6));
    final weekStr = '${DateFormat('dd/MM').format(_currentWeekMonday)} To ${DateFormat('dd/MM').format(weekEnd)}';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Bar with FAP controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    // Year indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('YEAR ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                          Text('${_currentWeekMonday.year}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                    // Week selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _currentWeekMonday = _currentWeekMonday.subtract(const Duration(days: 7));
                              });
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(
                              children: [
                                const Text('WEEK ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                                Text(weekStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _currentWeekMonday = _currentWeekMonday.add(const Duration(days: 7));
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    // Filter: All classes vs Selected class
                    FilterChip(
                      label: Text(_showAllClasses ? 'Tất cả ${_parsedSheets.length} lớp học' : 'Chỉ lớp ${_selectedSheet!.className}'),
                      selected: _showAllClasses,
                      onSelected: (val) => setState(() => _showAllClasses = val),
                    ),
                    // Switch view: FAP table vs List
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Lịch tuần (FAP)'), icon: Icon(Icons.grid_view, size: 16)),
                        ButtonSegment(value: false, label: Text('Danh sách'), icon: Icon(Icons.view_list, size: 16)),
                      ],
                      selected: {_isFapWeeklyView},
                      onSelectionChanged: (set) => setState(() => _isFapWeeklyView = set.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _isSyncing ? null : () => _syncToCloud(showFeedback: true),
                icon: _isSyncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ Google Sheet'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1D4ED8),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  backgroundColor: const Color(0xFFEFF6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedIndex = 2),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Bắt đầu Điểm danh Live'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // View Content
          Expanded(
            child: _isFapWeeklyView ? _buildFapWeeklyTableView() : _buildScheduleListView(),
          ),
        ],
      ),
    );
  }

  // --- FAP Weekly Timetable Grid ---
  Widget _buildFapWeeklyTableView() {
    if (_allSheetLessons.isEmpty && _parsedSheets.isNotEmpty) {
      _generateAllLessons();
    }

    final days = List.generate(7, (i) => _currentWeekMonday.add(Duration(days: i)));
    final dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const headerColor = Color(0xFF337AB7); // FAP Classic Blue

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 980 ? 980.0 : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Table(
                  border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1),
                  columnWidths: const {
                    0: FixedColumnWidth(92),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                    3: FlexColumnWidth(),
                    4: FlexColumnWidth(),
                    5: FlexColumnWidth(),
                    6: FlexColumnWidth(),
                    7: FlexColumnWidth(),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    // Header Row
                    TableRow(
                      decoration: const BoxDecoration(color: headerColor),
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                          child: const Text(
                            'YEAR / WEEK',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        ...List.generate(7, (i) {
                          final d = days[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(dayNames[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(DateFormat('dd/MM').format(d), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                    // Rows for Slots 1 to 8
                    ...List.generate(8, (slotIndex) {
                      final slotNumber = slotIndex + 1;
                      final times = AppConstants.dailySlots[slotNumber];
                      final isEven = slotIndex % 2 == 0;

                      return TableRow(
                        decoration: BoxDecoration(
                          color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                        ),
                        children: [
                          // Slot Label
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: const Color(0xFFF1F5F9),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Slot $slotNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                if (times != null) ...[
                                  const SizedBox(height: 3),
                                  Text('${times.$1}\n${times.$2}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), height: 1.2)),
                                ],
                              ],
                            ),
                          ),
                          // 7 Days
                          ...List.generate(7, (dayIdx) {
                            final currentDay = days[dayIdx];
                            return Container(
                              constraints: const BoxConstraints(minHeight: 84),
                              padding: const EdgeInsets.all(3),
                              child: _buildFapCell(currentDay, slotNumber),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFapCell(DateTime day, int slotNumber) {
    if (_allSheetLessons.isEmpty && _parsedSheets.isNotEmpty) {
      _generateAllLessons();
    }

    final matchingLessons = <({ParsedSheetResult sheet, LessonSchedule lesson})>[];

    if (_showAllClasses) {
      for (final sheet in _parsedSheets) {
        final lessons = _allSheetLessons[sheet.sheetName] ?? [];
        for (final l in lessons) {
          if (l.date.year == day.year && l.date.month == day.month && l.date.day == day.day && l.dailySlot == slotNumber) {
            matchingLessons.add((sheet: sheet, lesson: l));
          }
        }
      }
    } else if (_selectedSheet != null) {
      final lessons = _generatedLessons.isNotEmpty
          ? _generatedLessons
          : (_allSheetLessons[_selectedSheet!.sheetName] ?? []);
      for (final l in lessons) {
        if (l.date.year == day.year && l.date.month == day.month && l.date.day == day.day && l.dailySlot == slotNumber) {
          matchingLessons.add((sheet: _selectedSheet!, lesson: l));
        }
      }
    }

    if (matchingLessons.isEmpty) {
      return const Center(
        child: Text('-', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 16)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: matchingLessons.map((item) {
        final isCurrent = _activeLesson == item.lesson && _selectedSheet == item.sheet;
        final isWindowOpenHere = _isWindowOpen &&
            _selectedSheet?.sheetName == item.sheet.sheetName &&
            _activeLesson?.sequenceNumber == item.lesson.sequenceNumber;
        final isAttended = _isSlotAttended(item.sheet.sheetName, item.lesson.sequenceNumber);

        return InkWell(
          onTap: () {
            setState(() {
              _selectedSheet = item.sheet;
              _configuredSlotCount = item.sheet.detectedSlotCount;
              _generatedLessons = _allSheetLessons[item.sheet.sheetName] ?? [];
              _activeLesson = item.lesson;
              _getSlotAttendance(item.sheet.sheetName, item.lesson.sequenceNumber, roster: item.sheet.roster);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đã chọn Slot ${item.lesson.sequenceNumber}: ${item.sheet.subjectCode} - Lớp ${item.sheet.className}'),
                action: SnackBarAction(
                  label: 'Điểm danh ngay',
                  onPressed: () => setState(() => _selectedIndex = 2),
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              color: isCurrent ? const Color(0xFFF0F7FF) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrent ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                width: isCurrent ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isCurrent ? const Color(0xFF2563EB).withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.03),
                  blurRadius: isCurrent ? 6 : 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Subject Code & Class Name with Wrap to prevent overflow
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    Text(
                      item.sheet.subjectCode,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        item.sheet.className,
                        style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Slot sequence
                Text(
                  'Buổi ${item.lesson.sequenceNumber.toString().padLeft(2, '0')} / ${item.sheet.detectedSlotCount}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // Status badge with Flexible to prevent overflow
                if (isWindowOpenHere)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF93C5FD)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.radio_button_checked_rounded, size: 9, color: Color(0xFF2563EB)),
                        SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'Đang mở ca',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (isAttended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 9, color: Color(0xFF16A34A)),
                        SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'Đã điểm danh',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded, size: 9, color: Color(0xFF64748B)),
                        SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'Chưa điểm danh',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                // Time pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${item.lesson.startTime} - ${item.lesson.endTime}',
                    style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Alternative List View for Schedule ---
  Widget _buildScheduleListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: Colors.blue.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ngày bắt đầu buổi học đầu tiên:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _firstLessonDate,
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2027, 12, 31),
                          );
                          if (picked != null) {
                            setState(() {
                              _firstLessonDate = picked;
                              _generateLessonsForSheet();
                              _generateAllLessons();
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(DateFormat('EEEE, dd/MM/yyyy').format(_firstLessonDate)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Số lượng buổi học (Slot count):', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _configuredSlotCount > 1
                                ? () {
                                    setState(() {
                                      _configuredSlotCount--;
                                      _generateLessonsForSheet();
                                      _generateAllLessons();
                                    });
                                  }
                                : null,
                          ),
                          Text('$_configuredSlotCount slots', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              setState(() {
                                _configuredSlotCount++;
                                _generateLessonsForSheet();
                                _generateAllLessons();
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Danh sách ${_generatedLessons.length} buổi học đã tạo:', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              itemCount: _generatedLessons.length,
              itemBuilder: (context, index) {
                final lesson = _generatedLessons[index];
                final isCurrentActive = _activeLesson == lesson;
                return ListTile(
                  selected: isCurrentActive,
                  leading: CircleAvatar(
                    backgroundColor: isCurrentActive ? Colors.blue.shade700 : Colors.grey.shade200,
                    foregroundColor: isCurrentActive ? Colors.white : Colors.black87,
                    child: Text('${lesson.sequenceNumber}'),
                  ),
                  title: Text(
                    'Slot ${lesson.sequenceNumber.toString().padLeft(2, '0')} - ${DateFormat('dd/MM/yyyy (EEEE)').format(lesson.date)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('Ca ${lesson.dailySlot}: ${lesson.startTime} - ${lesson.endTime}'),
                  trailing: isCurrentActive
                      ? const Chip(label: Text('Đang chọn'), backgroundColor: Colors.blue)
                      : TextButton(
                          onPressed: () => setState(() => _activeLesson = lesson),
                          child: const Text('Chọn buổi này'),
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // --- View 3: Live Attendance & Dynamic QR ---
  Widget _buildLiveAttendanceView() {
    final activeSeq = _activeLesson?.sequenceNumber.toString().padLeft(2, '0') ?? '01';
    final currentSlotAttendance = (_selectedSheet != null && _activeLesson != null)
        ? _getSlotAttendance(_selectedSheet!.sheetName, _activeLesson!.sequenceNumber, roster: _selectedSheet!.roster)
        : <String, LiveStudentAttendance>{};
    final presentCount = currentSlotAttendance.values.where((s) => s.status == AttendanceStatus.present).length;
    final absentCount = currentSlotAttendance.values.where((s) => s.status == AttendanceStatus.absent).length;
    final totalCount = currentSlotAttendance.length;

    final presentPct = totalCount > 0 ? ((presentCount / totalCount) * 100).toStringAsFixed(0) : '0';
    final absentPct = totalCount > 0 ? ((absentCount / totalCount) * 100).toStringAsFixed(0) : '0';

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Action Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Điểm danh Trực tiếp - Buổi $activeSeq',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        if (_selectedSheet != null) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Text(
                              '${_selectedSheet!.subjectCode} • ${_selectedSheet!.className}',
                              style: const TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Mã QR tự động đổi mới mỗi 15 giây. Nhấp vào tên sinh viên để đổi Có mặt (P) ⇄ Vắng mặt (A).',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSyncing ? null : () => _syncToCloud(showFeedback: true),
                icon: _isSyncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 20),
                label: Text(_isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ Google Sheet'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1D4ED8),
                  side: const BorderSide(color: Color(0xFFBFDBFE)),
                  backgroundColor: const Color(0xFFEFF6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _toggleAttendanceWindow,
                icon: Icon(_isWindowOpen ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded, size: 22),
                label: Text(
                  _isWindowOpen ? 'Dừng & Đóng Ca Điểm Danh' : 'Bắt đầu Mở Ca Điểm Danh',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isWindowOpen ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                  elevation: 2,
                  shadowColor: (_isWindowOpen ? const Color(0xFFDC2626) : const Color(0xFF2563EB)).withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 3 KPI Stat Cards
          Row(
            children: [
              _buildModernKpiCard(
                label: 'Có mặt (P)',
                value: '$presentCount',
                subtitle: '$presentPct% sĩ số',
                icon: Icons.check_circle_rounded,
                primaryColor: const Color(0xFF059669),
                backgroundColor: const Color(0xFFECFDF5),
                borderColor: const Color(0xFFA7F3D0),
              ),
              const SizedBox(width: 14),
              _buildModernKpiCard(
                label: 'Vắng mặt (A)',
                value: '$absentCount',
                subtitle: '$absentPct% sĩ số',
                icon: Icons.cancel_rounded,
                primaryColor: const Color(0xFFE11D48),
                backgroundColor: const Color(0xFFFFF1F2),
                borderColor: const Color(0xFFFECDD3),
              ),
              const SizedBox(width: 14),
              _buildModernKpiCard(
                label: 'Sĩ số Lớp',
                value: '$totalCount',
                subtitle: 'Sinh viên',
                icon: Icons.groups_rounded,
                primaryColor: const Color(0xFF1D4ED8),
                backgroundColor: const Color(0xFFEFF6FF),
                borderColor: const Color(0xFFBFDBFE),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Main Interactive Area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Projector QR Area
                Container(
                  width: 370,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.tv_rounded, size: 18, color: Color(0xFF475569)),
                              SizedBox(width: 6),
                              Text('Màn hình Máy chiếu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isWindowOpen ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isWindowOpen ? 'ĐANG PHÁT' : 'ĐÃ ĐÓNG',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isWindowOpen ? const Color(0xFF15803D) : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isWindowOpen && _currentQrToken.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: QrImageView(
                            data: _currentQrToken,
                            version: QrVersions.auto,
                            size: 230.0,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            value: _secondsRemaining / 15.0,
                            backgroundColor: const Color(0xFFF1F5F9),
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF2563EB)),
                            const SizedBox(width: 4),
                            Text(
                              'Đổi mã QR sau: $_secondsRemaining giây',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.qr_code_2_rounded, size: 84, color: Color(0xFFCBD5E1)),
                        ),
                        const SizedBox(height: 16),
                        const Text('Ca điểm danh đang đóng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                        const SizedBox(height: 8),
                        const Text(
                          'Nhấn nút xanh "Bắt đầu Mở Ca Điểm Danh" ở góc trên để mở và chiếu mã QR cho sinh viên.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 20),

                // Live Roster Grid with Manual Override
                Expanded(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text('Danh sách sinh viên', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$totalCount sinh viên',
                                      style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(
                                width: 220,
                                height: 36,
                                child: TextField(
                                  onChanged: (val) => setState(() => _liveSearchQuery = val),
                                  decoration: InputDecoration(
                                    hintText: 'Tìm sinh viên, MSSV...',
                                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Color(0xFF94A3B8)),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final filteredStudents = currentSlotAttendance.values.where((st) {
                                if (_liveSearchQuery.isEmpty) return true;
                                final q = _liveSearchQuery.toLowerCase();
                                return st.studentName.toLowerCase().contains(q) ||
                                    st.rollNumber.toLowerCase().contains(q) ||
                                    st.studentEmail.toLowerCase().contains(q);
                              }).toList();

                              if (filteredStudents.isEmpty) {
                                return const Center(
                                  child: Text('Không tìm thấy sinh viên nào.', style: TextStyle(color: Color(0xFF64748B))),
                                );
                              }

                              return ListView.separated(
                                itemCount: filteredStudents.length,
                                separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                                itemBuilder: (context, index) {
                                  final student = filteredStudents[index];
                                  final isPresent = student.status == AttendanceStatus.present;
                                  final isAbsent = student.status == AttendanceStatus.absent;

                                  return ListTile(
                                    onTap: () => _toggleStudentAttendance(student.studentEmail),
                                    hoverColor: const Color(0xFFF8FAFC),
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      foregroundColor: const Color(0xFF334155),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            student.studentName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Text(
                                            student.rollNumber,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(student.studentEmail, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // High-clarity, distinct status toggle button
                                        Tooltip(
                                          message: isPresent ? 'Nhấn để chuyển sang Vắng mặt' : 'Nhấn để chuyển sang Có mặt',
                                          child: ElevatedButton.icon(
                                            onPressed: () => _toggleStudentAttendance(student.studentEmail),
                                            icon: Icon(
                                              isPresent ? Icons.check_circle_rounded : isAbsent ? Icons.cancel_rounded : Icons.help_outline_rounded,
                                              size: 15,
                                              color: Colors.white,
                                            ),
                                            label: Text(
                                              isPresent ? 'Có mặt (P)' : isAbsent ? 'Vắng mặt (A)' : 'Chưa ghi (-)',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isPresent
                                                  ? const Color(0xFF059669)
                                                  : isAbsent
                                                      ? const Color(0xFFDC2626)
                                                      : const Color(0xFF64748B),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              elevation: 1,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () => _simulateStudentCheckIn(student.studentEmail),
                                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 14),
                                          label: const Text('Quét thử', style: TextStyle(fontSize: 11.5)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernKpiCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color primaryColor,
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: primaryColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 24)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(subtitle, style: TextStyle(color: primaryColor.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- View 4: Export ---
  Widget _buildExportView() {
    if (_parsedSheets.isEmpty) {
      return const Center(child: Text('Vui lòng nhập tệp bảng điểm ở Bước 1 trước.'));
    }

    final targetSheet = _exportSelectedSheet ?? _selectedSheet ?? _parsedSheets.first;
    final totalSlots = targetSheet.detectedSlotCount;
    final attendedSlotCount = List.generate(totalSlots, (i) => i + 1)
        .where((slot) => _isSlotAttended(targetSheet.sheetName, slot))
        .length;

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Xuất Báo Cáo Điểm Danh', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Chọn lớp và các slot cần xuất (1 slot, nhiều slot hoặc toàn bộ $totalSlots slot)',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Main Config Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Class offering selection
                  Row(
                    children: [
                      const Text('Chọn Lớp học: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 12),
                      DropdownButton<ParsedSheetResult>(
                        value: _parsedSheets.contains(targetSheet) ? targetSheet : _parsedSheets.first,
                        borderRadius: BorderRadius.circular(10),
                        items: _parsedSheets.map((sheet) {
                          return DropdownMenuItem<ParsedSheetResult>(
                            value: sheet,
                            child: Text(
                              '${sheet.subjectCode} - Lớp ${sheet.className} (${sheet.detectedSlotCount} slots, ${sheet.roster.length} SV)',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
                        onChanged: (newSheet) {
                          if (newSheet != null) {
                            setState(() {
                              _exportSelectedSheet = newSheet;
                              _selectAllExportSlots(newSheet);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Slot Selection Header & Quick Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('Chọn các Slot cần xuất: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Đã chọn ${_exportSelectedSlots.length} / $totalSlots slots',
                              style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectAllExportSlots(targetSheet);
                              });
                            },
                            icon: const Icon(Icons.select_all_rounded, size: 16),
                            label: Text('Tất cả $totalSlots slots'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1E293B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: attendedSlotCount > 0
                                ? () {
                                    setState(() {
                                      _selectAttendedExportSlots(targetSheet);
                                    });
                                  }
                                : null,
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                            label: Text('Chỉ slot đã điểm danh ($attendedSlotCount)'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFFECFDF5),
                              foregroundColor: const Color(0xFF047857),
                              side: const BorderSide(color: Color(0xFFA7F3D0)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _exportSelectedSlots.clear();
                              });
                            },
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            label: const Text('Bỏ chọn tất cả'),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Slot Chips Grid
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(totalSlots, (index) {
                      final slotNum = index + 1;
                      final isSelected = _exportSelectedSlots.contains(slotNum);
                      final isAttended = _isSlotAttended(targetSheet.sheetName, slotNum);

                      return FilterChip(
                        selected: isSelected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Slot ${slotNum.toString().padLeft(2, '0')}'),
                            if (isAttended) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                            ],
                          ],
                        ),
                        backgroundColor: isAttended ? const Color(0xFFF0FDF4) : Colors.white,
                        selectedColor: isAttended ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                        checkmarkColor: isAttended ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                        side: BorderSide(
                          color: isSelected
                              ? (isAttended ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD))
                              : const Color(0xFFE2E8F0),
                        ),
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _exportSelectedSlots.add(slotNum);
                            } else {
                              _exportSelectedSlots.remove(slotNum);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Export Action Buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _exportSelectedSlots.isNotEmpty ? () => _exportCsv(targetSheet) : null,
                        icon: const Icon(Icons.description_rounded, size: 20),
                        label: Text('Xuất file CSV (${_exportSelectedSlots.length} slots)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                          elevation: 2,
                          shadowColor: const Color(0xFF2563EB).withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _exportSelectedSlots.isNotEmpty ? () => _exportXlsx(targetSheet) : null,
                        icon: const Icon(Icons.table_view_rounded, size: 20),
                        label: Text('Xuất file Excel (.xlsx) (${_exportSelectedSlots.length} slots)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                          elevation: 2,
                          shadowColor: const Color(0xFF16A34A).withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          // Preview table summary
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xem trước dữ liệu các slot được chọn (${targetSheet.className} - ${targetSheet.subjectCode})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _exportSelectedSlots.isEmpty
                          ? const Center(child: Text('Chưa có slot nào được chọn để xuất.'))
                          : ListView(
                              children: [
                                DataTable(
                                  columnSpacing: 24,
                                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                  columns: [
                                    const DataColumn(label: Text('Slot', style: TextStyle(fontWeight: FontWeight.bold))),
                                    const DataColumn(label: Text('Trạng thái điểm danh', style: TextStyle(fontWeight: FontWeight.bold))),
                                    const DataColumn(label: Text('Có mặt (P)', style: TextStyle(fontWeight: FontWeight.bold))),
                                    const DataColumn(label: Text('Vắng mặt (A)', style: TextStyle(fontWeight: FontWeight.bold))),
                                    const DataColumn(label: Text('Chưa ghi (-)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: (_exportSelectedSlots.toList()..sort()).map((slotNum) {
                                    final slotMap = _attendanceStore[targetSheet.sheetName]?[slotNum];
                                    final isAttended = _isSlotAttended(targetSheet.sheetName, slotNum);
                                    final pCount = slotMap?.values.where((s) => s.status == AttendanceStatus.present).length ?? 0;
                                    final aCount = slotMap?.values.where((s) => s.status == AttendanceStatus.absent).length ?? 0;
                                    final blankCount = targetSheet.roster.length - pCount - aCount;

                                    return DataRow(
                                      cells: [
                                        DataCell(Text('Slot ${slotNum.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.w600))),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isAttended ? Colors.green.shade50 : Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: isAttended ? Colors.green.shade300 : Colors.grey.shade300),
                                            ),
                                            child: Text(
                                              isAttended ? 'Đã điểm danh' : 'Chưa điểm danh',
                                              style: TextStyle(
                                                color: isAttended ? Colors.green.shade800 : Colors.grey.shade700,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(Text('$pCount', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                                        DataCell(Text('$aCount', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                                        DataCell(Text('$blankCount', style: const TextStyle(color: Colors.grey))),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(ParsedSheetResult targetSheet) async {
    final sortedSlots = _exportSelectedSlots.toList()..sort();
    if (sortedSlots.isEmpty) return;

    final studentsData = _collectExportData(targetSheet, sortedSlots);
    final slotSuffix = sortedSlots.length == targetSheet.detectedSlotCount
        ? 'all${sortedSlots.length}slots'
        : 'slots_${sortedSlots.join('_')}';
    final outPath = 'attendance_${targetSheet.className}_$slotSuffix.csv';

    await _exportService.exportToCsv(
      filePath: outPath,
      classCode: targetSheet.className,
      selectedLessonNumbers: sortedSlots,
      studentsData: studentsData,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xuất thành công file CSV (UTF-8 BOM): $outPath'),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

  Future<void> _exportXlsx(ParsedSheetResult targetSheet) async {
    final sortedSlots = _exportSelectedSlots.toList()..sort();
    if (sortedSlots.isEmpty) return;

    final studentsData = _collectExportData(targetSheet, sortedSlots);
    final slotSuffix = sortedSlots.length == targetSheet.detectedSlotCount
        ? 'all${sortedSlots.length}slots'
        : 'slots_${sortedSlots.join('_')}';
    final outPath = 'attendance_${targetSheet.className}_$slotSuffix.xlsx';

    await _exportService.exportToXlsx(
      filePath: outPath,
      classCode: targetSheet.className,
      selectedLessonNumbers: sortedSlots,
      studentsData: studentsData,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xuất thành công file Excel: $outPath'),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

  List<Map<String, dynamic>> _collectExportData(ParsedSheetResult targetSheet, List<int> sortedSlots) {
    final studentsData = <Map<String, dynamic>>[];
    for (final student in targetSheet.roster) {
      final item = <String, dynamic>{
        'rollNumber': student.rollNumber,
        'fullName': student.fullName,
        'email': student.email,
      };

      for (final slotSeq in sortedSlots) {
        final liveStudent = _attendanceStore[targetSheet.sheetName]?[slotSeq]?[student.email.toLowerCase()];
        final statusStr = liveStudent?.status == AttendanceStatus.present
            ? 'P'
            : liveStudent?.status == AttendanceStatus.absent
                ? 'A'
                : '';
        item['lesson_$slotSeq'] = statusStr;
      }

      studentsData.add(item);
    }
    return studentsData;
  }
}
