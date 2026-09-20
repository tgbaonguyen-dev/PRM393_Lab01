import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../import/models/import_models.dart';
import '../session/qr_display_screen.dart';
import '../export/export_dialog.dart';
import '../attendance/services/attendance_storage_service.dart';
import '../../shared/m1_snackbar.dart';
import '../../shell/app_shell.dart';
import 'models/schedule_models.dart';
import 'services/schedule_code_parser.dart';
import 'services/schedule_api_client.dart';
import 'services/schedule_generator.dart';
import 'services/schedule_overview.dart';

class ScheduleGeneratorScreen extends StatefulWidget {
  final List<ImportedClass> importedClasses;
  final DateTime semesterStart;
  final int initialClassIndex;
  final Map<String, List<ClassLesson>>? initialSchedules;

  const ScheduleGeneratorScreen({
    super.key,
    required this.importedClasses,
    required this.semesterStart,
    this.initialClassIndex = 0,
    this.initialSchedules,
  }) : assert(importedClasses.length > 0);

  @override
  State<ScheduleGeneratorScreen> createState() =>
      _ScheduleGeneratorScreenState();
}

class _ScheduleGeneratorScreenState extends State<ScheduleGeneratorScreen> {
  static const _allClasses = '__all_classes__';
  static const _dayNames = <String>[
    'THỨ HAI',
    'THỨ BA',
    'THỨ TƯ',
    'THỨ NĂM',
    'THỨ SÁU',
    'THỨ BẢY',
    'CHỦ NHẬT',
  ];

  late final List<ImportedClass> _classes;
  final Map<String, List<ClassLesson>> _schedules = {};
  late DateTime _weekStart;
  String _filter = _allClasses;
  String? _selectedKey;
  String? _suggestedKey;
  bool _isSaving = false;
  bool _isSyncingAttendance = false;
  final _apiClient = ScheduleApiClient();
  Map<String, Map<int, Map<String, String>>> _attendanceStore = {};

  ScheduledLessonView? get _selectedLesson => ScheduleOverview.findByKey(
    key: _selectedKey,
    classes: _classes,
    schedules: _schedules,
  );

  String? get _classFilter => _filter == _allClasses ? null : _filter;

  List<int> get _visibleSlots {
    final slots = ScheduleOverview.allLessons(
      classes: _classes,
      schedules: _schedules,
      classFilter: _classFilter,
    ).map((item) => item.lesson.dailySlot).toSet().toList()..sort();
    return slots;
  }

  @override
  void initState() {
    super.initState();
    _classes = List<ImportedClass>.unmodifiable(widget.importedClasses);
    _weekStart = ScheduleOverview.startOfWeek(widget.semesterStart);
    _generateAllSchedules();
    _loadAttendanceStore();
    AppNavigationController.instance.addListener(_onNavigationChanged);

    final current = ScheduleOverview.findCurrentLesson(
      classes: _classes,
      schedules: _schedules,
      now: DateTime.now(),
    );
    if (current != null) {
      _suggestedKey = current.key;
      _selectedKey = current.key;
      _weekStart = ScheduleOverview.startOfWeek(current.lesson.date);
      return;
    }

    final index = widget.initialClassIndex.clamp(0, _classes.length - 1);
    final firstLessons = _schedules[_classes[index].sourceSheetName]!;
    if (firstLessons.isNotEmpty) {
      _selectedKey = '${_classes[index].sourceSheetName}:${firstLessons.first.lessonId}';
      _weekStart = ScheduleOverview.startOfWeek(firstLessons.first.date);
    }
  }

  @override
  void dispose() {
    AppNavigationController.instance.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    if (mounted && AppNavigationController.instance.currentIndex == 0) {
      _loadAttendanceStore();
    }
  }

  /// Nạp ma trận điểm danh từ local storage
  Future<void> _loadAttendanceStore() async {
    try {
      final storage = AttendanceStorageService();
      final store = await storage.loadStore();
      if (mounted) {
        setState(() {
          _attendanceStore = store;
        });
      }
    } catch (_) {}
  }

  /// Kiểm tra thông tin điểm danh của một buổi học trên lịch
  ({bool isAttended, int presentCount, int totalCount}) _getLessonAttendanceInfo(
    ScheduledLessonView item,
  ) {
    final compositeKey =
        '${item.importedClass.subjectCode} - ${item.importedClass.classCode}';
    final candidateKeys = [
      compositeKey,
      item.importedClass.sourceSheetName,
      item.importedClass.classCode,
      if (item.importedClass.sourceSheetName.contains('_'))
        item.importedClass.sourceSheetName.split('_').last,
      '${item.importedClass.scheduleCode}_${item.importedClass.subjectCode}_${item.importedClass.classCode}',
    ];

    Map<int, Map<String, String>> classAttendance = const {};
    for (final key in candidateKeys) {
      if (_attendanceStore.containsKey(key)) {
        classAttendance = _attendanceStore[key]!;
        break;
      }
    }

    final slotAttendance = classAttendance[item.lesson.sequenceNumber];
    if (slotAttendance == null || slotAttendance.isEmpty) {
      return (
        isAttended: false,
        presentCount: 0,
        totalCount: item.importedClass.students.length,
      );
    }

    final presentCount =
        slotAttendance.values.where((status) => status == 'P').length;
    final isAttended = presentCount > 0 ||
        (slotAttendance.length >= item.importedClass.students.length &&
            slotAttendance.isNotEmpty);

    final total = item.importedClass.students.isNotEmpty
        ? item.importedClass.students.length
        : slotAttendance.length;

    return (
      isAttended: isAttended,
      presentCount: presentCount,
      totalCount: total,
    );
  }

  /// Đồng bộ toàn bộ dữ liệu điểm danh mới nhất từ Google Sheet (qua Backend)
  Future<void> _syncFromGoogleSheet({bool showToast = true}) async {
    if (_isSyncingAttendance) return;
    if (mounted) setState(() => _isSyncingAttendance = true);
    try {
      final success = await AttendanceStorageService().pullFromRemote();
      await _loadAttendanceStore();
      if (!mounted) return;
      if (showToast) {
        if (success) {
          M1SnackBar.show(
            context,
            'Đã đồng bộ dữ liệu điểm danh mới nhất từ Google Sheet.',
          );
        } else {
          M1SnackBar.show(
            context,
            'Không thể kết nối với Google Sheet để đồng bộ.',
            type: M1NoticeType.warning,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (showToast) {
        M1SnackBar.show(
          context,
          'Lỗi khi đồng bộ Google Sheet: $e',
          type: M1NoticeType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingAttendance = false);
      }
    }
  }

  void _generateAllSchedules() {
    for (final importedClass in _classes) {
      final stored = widget.initialSchedules?[importedClass.sourceSheetName];
      if (stored != null && stored.isNotEmpty) {
        _schedules[importedClass.sourceSheetName] = List.of(stored);
        continue;
      }
      final firstDate = ScheduleGenerator.firstTeachingDateOnOrAfter(
        scheduleCode: importedClass.scheduleCode,
        semesterStart: widget.semesterStart,
      );
      _schedules[importedClass.sourceSheetName] = ScheduleGenerator.generate(
        classOfferingId: importedClass.offeringId,
        scheduleCode: importedClass.scheduleCode,
        firstDate: firstDate,
        lessonCount: importedClass.lessonCount,
      );
    }
  }

  Future<void> _saveSchedules() async {
    setState(() => _isSaving = true);
    try {
      final message = await _apiClient.saveSchedules(
        importedClasses: _classes,
        schedules: _schedules,
      );
      if (!mounted) return;
      M1SnackBar.show(context, message);
    } catch (error) {
      if (!mounted) return;
      M1SnackBar.show(
        context,
        'Không thể lưu lịch: $error',
        type: M1NoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _changeWeek(int weeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: weeks * 7));
    });
  }

  void _selectLesson(ScheduledLessonView item) {
    setState(() {
      _selectedKey = item.key;
    });
    _loadAttendanceStore();
  }

  Future<void> _openQrScreen(ScheduledLessonView item) async {
    final rosterList = item.importedClass.students
        .map(
          (s) => {
            'rollNumber': s.rollNumber,
            'fullName': s.fullName,
            'email': s.email,
            'memberCode': s.memberCode,
          },
        )
        .toList();

    AppNavigationController.instance.openQrForSession(
      sessionId: item.lesson.lessonId,
      classId: item.importedClass.offeringId,
      className:
          '${item.importedClass.subjectCode} - ${item.importedClass.classCode}',
      lessonLabel:
          'Buổi ${item.lesson.sequenceNumber}/${item.importedClass.lessonCount}',
      roster: rosterList,
    );

    final hasShell = context.findAncestorStateOfType<State<AppShell>>() != null;
    if (!hasShell) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QrDisplayScreen(
            classId: item.importedClass.offeringId,
            sessionId: item.lesson.lessonId,
            className:
                '${item.importedClass.subjectCode} - ${item.importedClass.classCode}',
            lessonLabel:
                'Buổi ${item.lesson.sequenceNumber}/${item.importedClass.lessonCount}',
            roster: rosterList,
          ),
        ),
      );

      // Tải lại ma trận điểm danh sau khi kết thúc phiên QR để cập nhật dấu "Đã điểm danh" ngay lập tức trên lịch
      await _loadAttendanceStore();
    }
  }

  int _calculateWeekNumber() {
    final diffDays = _weekStart
        .difference(ScheduleOverview.startOfWeek(widget.semesterStart))
        .inDays;
    final num = (diffDays / 7).floor() + 1;
    return num > 0 ? num : 1;
  }

  Future<void> _changeSelectedLessonDate() async {
    final selected = _selectedLesson;
    if (selected == null) {
      M1SnackBar.show(
        context,
        'Hãy chọn một buổi học trên lịch trước.',
        type: M1NoticeType.warning,
      );
      return;
    }

    final newDate = await showDatePicker(
      context: context,
      helpText: 'Chọn ngày học bù hoặc ngày được đổi lịch',
      confirmText: 'Đổi lịch',
      initialDate: selected.lesson.date,
      firstDate: DateTime(widget.semesterStart.year - 1),
      lastDate: DateTime(widget.semesterStart.year + 2, 12, 31),
    );
    if (newDate == null || !mounted) return;

    final newSlot = await _pickReplacementSlot(selected.lesson.dailySlot);
    if (newSlot == null || !mounted) return;

    try {
      final key = selected.importedClass.sourceSheetName;
      final updated = ScheduleGenerator.replaceLessonDate(
        lessons: _schedules[key]!,
        sequenceNumber: selected.lesson.sequenceNumber,
        newDate: newDate,
        newDailySlot: newSlot,
      );
      setState(() {
        _schedules[key] = updated;
        _weekStart = ScheduleOverview.startOfWeek(newDate);
      });
      M1SnackBar.show(
        context,
        'Đã đổi Buổi ${selected.lesson.sequenceNumber} sang ${DateFormat('dd/MM/yyyy').format(newDate)}, Slot $newSlot. Nhấn Lưu lịch học để ghi nhận thay đổi.',
        type: M1NoticeType.warning,
      );
    } on ArgumentError catch (error) {
      M1SnackBar.show(
        context,
        error.message?.toString() ?? 'Không thể đổi lịch.',
        type: M1NoticeType.error,
      );
    }
  }

  Future<int?> _pickReplacementSlot(int currentSlot) async {
    var selectedSlot = currentSlot;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Chọn slot học'),
          content: DropdownButtonFormField<int>(
            initialValue: selectedSlot,
            decoration: const InputDecoration(labelText: 'Slot mới'),
            items: List.generate(5, (index) {
              final slot = index + 1;
              final time = ScheduleCodeParser.slotTimes[slot]!;
              return DropdownMenuItem(
                value: slot,
                child: Text('Slot $slot (${time.$1}–${time.$2})'),
              );
            }),
            onChanged: (value) {
              if (value != null) setDialogState(() => selectedSlot = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selectedSlot),
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
  }

  // Bảng màu Notion Workspace / Academic Minimalist
  static const _canvasBg = Color(0xFFFAF9F6);
  static const _borderColor = Color(0xFFE3E2DE);
  static const _textPrimary = Color(0xFF37352F);
  static const _textSecondary = Color(0xFF787774);
  static const _textTertiary = Color(0xFF9B9A97);

  // Subject theme styling (Notion database tag aesthetic)
  static ({Color bg, Color text, Color border, Color accent}) _subjectTheme(String code) {
    final upper = code.toUpperCase();
    if (upper.contains('PRM')) {
      return (
        bg: const Color(0xFFEFF6FF),
        text: const Color(0xFF1D4ED8),
        border: const Color(0xFFBFDBFE),
        accent: const Color(0xFF2563EB),
      );
    }
    if (upper.contains('PRN')) {
      return (
        bg: const Color(0xFFF5F3FF),
        text: const Color(0xFF6D28D9),
        border: const Color(0xFFDDD6FE),
        accent: const Color(0xFF7C3AED),
      );
    }
    if (upper.contains('SWD')) {
      return (
        bg: const Color(0xFFECFDF5),
        text: const Color(0xFF047857),
        border: const Color(0xFFA7F3D0),
        accent: const Color(0xFF059669),
      );
    }
    return (
      bg: const Color(0xFFFFFBEB),
      text: const Color(0xFFB45309),
      border: const Color(0xFFFDE68A),
      accent: const Color(0xFFD97706),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvasBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTightHeight = constraints.maxHeight < 680;
          final content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pageHeader(),
                const SizedBox(height: 10),
                _toolbar(),
                const SizedBox(height: 8),
                _classFilterBar(),
                const SizedBox(height: 10),
                _selectionPanel(),
                const SizedBox(height: 10),
                if (isTightHeight)
                  SizedBox(
                    height: 480,
                    child: _weeklyTable(),
                  )
                else
                  Expanded(child: _weeklyTable()),
                const SizedBox(height: 8),
                _bottomStatusBar(),
              ],
            ),
          );

          if (isTightHeight) {
            return SingleChildScrollView(
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _classFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list_rounded, size: 14, color: _textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Lớp:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            _filterChip(
              label: 'Tất cả (${_classes.length})',
              isSelected: _filter == _allClasses,
              onTap: () => setState(() => _filter = _allClasses),
            ),
            ..._classes.map((item) {
              final isSelected = _filter == item.sourceSheetName;
              final theme = _subjectTheme(item.subjectCode);
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InkWell(
                  onTap: () => setState(() => _filter = item.sourceSheetName),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? theme.bg : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? theme.accent : _borderColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${item.subjectCode} · ${item.classCode}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? theme.text : _textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF37352F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF37352F) : _borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : _textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _pageHeader() {
    final weekNum = _calculateWeekNumber();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lịch Giảng Dạy Tuần $weekNum',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Lịch giảng dạy chính khóa, phòng máy lab và lịch sinh hoạt chuyên môn',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _toolbar() {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final range =
        '${DateFormat('dd/MM').format(_weekStart)} – ${DateFormat('dd/MM').format(weekEnd)}';
    final totalLessons = _classes.fold<int>(
      0,
      (total, item) => total + item.lessonCount,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Class count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1EF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: Text(
              '${_classes.length} lớp • $totalLessons buổi',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
            ),
          ),

          // Week navigation: < Tuần range • year >
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                splashRadius: 14,
                onPressed: () => _changeWeek(-1),
                icon: const Icon(Icons.chevron_left, size: 18, color: _textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderColor, width: 1),
                ),
                child: Text(
                  'Tuần $range • ${_weekStart.year}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                splashRadius: 14,
                onPressed: () => _changeWeek(1),
                icon: const Icon(Icons.chevron_right, size: 18, color: _textPrimary),
              ),
            ],
          ),

          // Button Hôm Nay
          OutlinedButton(
            onPressed: () {
              setState(() {
                _weekStart = ScheduleOverview.startOfWeek(DateTime.now());
              });
            },
            child: const Text('Hôm Nay'),
          ),

          // Button Nhập File Lớp
          OutlinedButton(
            onPressed: () {
              AppNavigationController.instance.navigateToTab(2);
            },
            child: const Text('Nhập File Lớp'),
          ),

          // Button Xuất Báo Cáo
          OutlinedButton(
            onPressed: _openExportDialogFromSchedule,
            child: const Text('Xuất Báo Cáo'),
          ),

          // Button Lưu lịch học
          Tooltip(
            message:
                'Lưu lớp, danh sách sinh viên và lịch đã điều chỉnh vào hệ thống.',
            child: OutlinedButton(
              onPressed: _isSaving ? null : _saveSchedules,
              child: Text(_isSaving ? 'Đang lưu...' : 'Lưu lịch học'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionPanel() {
    final selected = _selectedLesson;
    final isCurrentSuggested = selected?.key == _suggestedKey;
    final selectedAttInfo = selected != null
        ? _getLessonAttendanceInfo(selected)
        : (isAttended: false, presentCount: 0, totalCount: 0);

    if (selected == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 15, color: _textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chưa chọn buổi học. Hãy nhấp vào một ô trên lịch để chọn buổi cần điểm danh hoặc đổi lịch.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 30),
              ),
              onPressed: _isSyncingAttendance
                  ? null
                  : () => _syncFromGoogleSheet(showToast: true),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSyncingAttendance)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                  Text(
                    _isSyncingAttendance
                        ? 'Đang đồng bộ...'
                        : 'Đồng bộ từ Google Sheet',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 30),
              ),
              onPressed: null,
              child: const Text('Đổi lịch buổi đã chọn', style: TextStyle(fontSize: 11.5)),
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: const Size(0, 30),
                backgroundColor: const Color(0xFF37352F),
                foregroundColor: Colors.white,
              ),
              onPressed: null,
              child: const Text('Mở điểm danh QR', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
      );
    }

    final theme = _subjectTheme(selected.importedClass.subjectCode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isCurrentSuggested ? const Color(0xFFC6E7D6) : _borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Bên trái: Thông tin buổi học và trạng thái điểm danh
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isCurrentSuggested
                        ? const Color(0xFF1F7A4D)
                        : theme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  '${selected.importedClass.subjectCode} · ${selected.importedClass.classCode}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F1EF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Buổi ${selected.lesson.sequenceNumber}/${selected.importedClass.lessonCount}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_outlined, size: 13, color: _textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${DateFormat('dd/MM/yyyy').format(selected.lesson.date)} · ${selected.lesson.startTime}–${selected.lesson.endTime}',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
                if (isCurrentSuggested)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF5F0),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFFC6E7D6)),
                    ),
                    child: const Text(
                      'Đang Diễn Ra',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F7A4D),
                      ),
                    ),
                  ),
                if (selectedAttInfo.isAttended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF5F0),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFFC6E7D6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 11,
                          color: Color(0xFF1F7A4D),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Đã điểm danh: ${selectedAttInfo.presentCount}/${selectedAttInfo.totalCount} có mặt',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1F7A4D),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Bên phải: Cụm nút hành động căn sát lề phải
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: _isSyncingAttendance
                    ? null
                    : () => _syncFromGoogleSheet(showToast: true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSyncingAttendance)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    Text(
                      _isSyncingAttendance
                          ? 'Đang đồng bộ...'
                          : 'Đồng bộ từ Google Sheet',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: _changeSelectedLessonDate,
                child: const Text('Đổi lịch buổi đã chọn', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: const Size(0, 30),
                  backgroundColor: const Color(0xFF37352F),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _openQrScreen(selected),
                child: const Text(
                  'Mở điểm danh QR',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openExportDialogFromSchedule() async {
    // Kéo dữ liệu mới nhất từ Google Sheet trước khi mở hộp thoại xuất
    await _syncFromGoogleSheet(showToast: false);

    final storage = AttendanceStorageService();
    final persistentStore = await storage.loadStore();

    final exportOptions = _classes.map((c) {
      final lessons = _schedules[c.sourceSheetName] ?? [];
      final lessonDates = <int, String>{};
      for (final l in lessons) {
        lessonDates[l.sequenceNumber] = DateFormat('yyyy-MM-dd').format(l.date);
      }
      final rosterList = c.students
          .map(
            (s) => {
              'rollNumber': s.rollNumber,
              'fullName': s.fullName,
              'email': s.email,
              'memberCode': s.memberCode,
            },
          )
          .toList();

      // Nạp dữ liệu P/A từ local storage (hoặc từ persistentStore)
      // QrDisplayScreen lưu với key "${subjectCode} - ${classCode}"
      final compositeKey = '${c.subjectCode} - ${c.classCode}';
      final classAttendance =
          persistentStore[compositeKey] ??
          persistentStore[c.sourceSheetName] ??
          persistentStore[c.classCode] ??
          <int, Map<String, String>>{};

      final attendanceData = <String, Map<int, String>>{};
      for (final s in c.students) {
        final emailKey = s.email.toLowerCase();
        final studentSlotMap = <int, String>{};
        classAttendance.forEach((slotNum, studentMap) {
          final status = studentMap[emailKey] ?? '';
          if (status.isNotEmpty) {
            studentSlotMap[slotNum] = status;
          }
        });
        attendanceData[emailKey] = studentSlotMap;
      }

      return ExportClassOption(
        subjectCode: c.subjectCode,
        className: c.classCode,
        semester: 'FA26',
        roster: rosterList,
        lessonDates: lessonDates,
        attendanceData: attendanceData,
      );
    }).toList();

    final initialClass = _selectedLesson?.importedClass ?? _classes.first;
    final initialOption = exportOptions.firstWhere(
      (o) =>
          o.subjectCode == initialClass.subjectCode &&
          o.className == initialClass.classCode,
      orElse: () => exportOptions.first,
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => ExportDialog(
        subjectCode: initialOption.subjectCode,
        className: initialOption.className,
        semester: initialOption.semester,
        roster: initialOption.roster,
        lessonDates: initialOption.lessonDates,
        attendanceData: initialOption.attendanceData,
        currentLessonSequence: _selectedLesson?.lesson.sequenceNumber,
        availableClasses: exportOptions,
      ),
    );
  }

  Widget _weeklyTable() {
    final visibleSlots = _visibleSlots;
    final days = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 1000
              ? 1000.0
              : constraints.maxWidth;
          return SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Table(
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: _borderColor, width: 1),
                    verticalInside: BorderSide(color: _borderColor, width: 1),
                  ),
                  columnWidths: const {
                    0: FixedColumnWidth(110),
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
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF7F6F3)),
                      children: [
                        const _HeaderCell(title: 'KHUNG GIỜ'),
                        ...List.generate(
                          7,
                          (index) {
                            final day = days[index];
                            final isToday = day.year == now.year &&
                                day.month == now.month &&
                                day.day == now.day;
                            return _HeaderCell(
                              title: _dayNames[index],
                              subtitle: DateFormat('dd/MM').format(day),
                              isToday: isToday,
                            );
                          },
                        ),
                      ],
                    ),
                    ...visibleSlots.map((slot) {
                      final time = ScheduleCodeParser.slotTimes[slot]!;
                      return TableRow(
                        decoration: const BoxDecoration(color: Colors.white),
                        children: [
                          Container(
                            constraints: const BoxConstraints(minHeight: 110),
                            color: const Color(0xFFFAF9F6),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Slot $slot',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${time.$1}–${time.$2}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...days.map((day) => _scheduleCell(day, slot)),
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

  Widget _scheduleCell(DateTime day, int slot) {
    var lessons = ScheduleOverview.lessonsForCell(
      classes: _classes,
      schedules: _schedules,
      date: day,
      dailySlot: slot,
      classFilter: _classFilter,
    );

    // Filter by searchQuery if any
    final query =
        AppNavigationController.instance.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      lessons = lessons.where((item) {
        final sub = item.importedClass.subjectCode.toLowerCase();
        final cls = item.importedClass.classCode.toLowerCase();
        return sub.contains(query) || cls.contains(query);
      }).toList();
    }

    if (lessons.isEmpty) {
      return const SizedBox(
        height: 110,
        child: Center(
          child: Text('—', style: TextStyle(color: Color(0xFFE3E2DE), fontSize: 13)),
        ),
      );
    }

    final hasConflict = lessons.length > 1;

    return Container(
      constraints: const BoxConstraints(minHeight: 110),
      padding: const EdgeInsets.all(5),
      decoration: hasConflict
          ? BoxDecoration(
              color: const Color(0xFFFFFBEB).withValues(alpha: 0.35),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasConflict)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFFCD34D), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 11,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      'Trùng slot (${lessons.length} lớp)',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ...lessons.map(_lessonCard),
        ],
      ),
    );
  }

  Widget _lessonCard(ScheduledLessonView item) {
    final selected = item.key == _selectedKey;
    final suggested = item.key == _suggestedKey;
    final theme = _subjectTheme(item.importedClass.subjectCode);
    final attInfo = _getLessonAttendanceInfo(item);

    final borderColor = suggested
        ? const Color(0xFF1F7A4D)
        : selected
            ? _textPrimary
            : (attInfo.isAttended ? const Color(0xFFC6E7D6) : _borderColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected
            ? const Color(0xFFF7F6F3)
            : (suggested
                ? const Color(0xFFFAFCFA)
                : (attInfo.isAttended ? const Color(0xFFFCFDFC) : Colors.white)),
        elevation: selected ? 1 : 0,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _selectLesson(item),
          onDoubleTap: () {
            _selectLesson(item);
            _openQrScreen(item);
          },
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Notion left colored accent bar
                Container(
                  width: 3.5,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      bottomLeft: Radius.circular(3),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: Subject code + Status Badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.importedClass.subjectCode,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            if (suggested) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEBF5F0),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'Đang Diễn Ra',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1F7A4D),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Class code badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.bg,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            item.importedClass.classCode,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: theme.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Sequence: Buổi 01 / 20 (satisfies test expectation)
                        Text(
                          'Buổi ${item.lesson.sequenceNumber.toString().padLeft(2, '0')} / ${item.importedClass.lessonCount}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),

                        // Time and student count
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.lesson.startTime}–${item.lesson.endTime}',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            if (item.importedClass.students.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${item.importedClass.students.length} SV',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  color: _textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Đánh dấu đã điểm danh trên card lịch
                        if (attInfo.isAttended) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEBF5F0),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                  color: const Color(0xFFC6E7D6), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 10,
                                  color: Color(0xFF1F7A4D),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    attInfo.presentCount > 0
                                        ? 'Đã điểm danh (${attInfo.presentCount}/${attInfo.totalCount})'
                                        : 'Đã điểm danh',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1F7A4D),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Action CTA if ongoing or selected
                        if (suggested || selected) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              _selectLesson(item);
                              _openQrScreen(item);
                            },
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 3.5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: suggested
                                    ? const Color(0xFFEBF5F0)
                                    : const Color(0xFFF1F1EF),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: suggested
                                      ? const Color(0xFFC6E7D6)
                                      : _borderColor,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                'Vào Điểm Danh QR',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: suggested
                                      ? const Color(0xFF1F7A4D)
                                      : _textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomStatusBar() {
    final totalLessons = _classes.fold<int>(
      0,
      (total, item) => total + item.lessonCount,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Legend
          Row(
            children: [
              _legendItem(const Color(0xFF1F7A4D), 'Đang Diễn Ra'),
              const SizedBox(width: 14),
              _legendItem(const Color(0xFFB87214), 'Sắp Tới'),
              const SizedBox(width: 14),
              _legendItem(const Color(0xFF787774), 'Đã Xong'),
            ],
          ),

          // Total
          Text(
            'Tổng Cộng ${_classes.length} Lớp • $totalLessons Buổi Học • Múi Giờ GMT+7',
            style: const TextStyle(
              fontSize: 11.5,
              color: _textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: _textSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isToday;

  const _HeaderCell({
    required this.title,
    this.subtitle,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: isToday
                      ? const Color(0xFF1F7A4D)
                      : const Color(0xFF37352F),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              if (isToday)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF5F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    'Hôm Nay',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1F7A4D),
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.inter(
                color: const Color(0xFF787774),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
