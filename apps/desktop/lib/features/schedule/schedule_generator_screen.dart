import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../import/models/import_models.dart';
import '../session/qr_display_screen.dart';
import '../export/export_dialog.dart';
import '../attendance/services/attendance_storage_service.dart';
import '../../shared/m1_snackbar.dart';
import '../../shared/notion_tokens.dart';
import '../../shared/workspace_ui.dart';
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

  late List<ImportedClass> _classes;
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
      _selectedKey =
          '${_classes[index].sourceSheetName}:${firstLessons.first.lessonId}';
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
  ({bool isAttended, int presentCount, int totalCount})
  _getLessonAttendanceInfo(ScheduledLessonView item) {
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

    final presentCount = slotAttendance.values
        .where((status) => status == 'P')
        .length;
    final isAttended =
        presentCount > 0 ||
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

  /// Đồng bộ toàn bộ dữ liệu điểm danh và lịch học mới nhất từ Google Sheet (qua Backend)
  Future<void> _syncFromGoogleSheet({bool showToast = true}) async {
    if (_isSyncingAttendance) return;
    if (mounted) setState(() => _isSyncingAttendance = true);
    try {
      final success = await AttendanceStorageService().pullFromRemote();
      await _loadAttendanceStore();

      if (_classes.isEmpty) {
        try {
          final saved = await _apiClient.loadSavedSchedules();
          if (saved.classes.isNotEmpty && mounted) {
            setState(() {
              _classes = saved.classes;
              _schedules.clear();
              _schedules.addAll(saved.schedules);
            });
            AppNavigationController.instance.activeClasses = saved.classes;
            AppNavigationController.instance.activeSchedules = saved.schedules;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      if (showToast) {
        if (success) {
          M1SnackBar.show(
            context,
            'Đã đồng bộ dữ liệu mới nhất từ Google Sheet.',
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

  static const _borderColor = NotionColors.hairline;
  static const _textPrimary = NotionColors.ink;
  static const _textSecondary = NotionColors.inkSecondary;
  static const _textTertiary = NotionColors.inkMuted;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: NotionColors.surface,
    body: WorkspacePage(
      header: [
        _pageHeader(),
        _notionControlsBar(),
        _selectionPanel(),
      ],
      body: _weeklyTable(),
      compactBodyHeight: 560,
    ),
  );

  Widget _pageHeader() {
    return WorkspaceHeader(
      icon: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1EF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.calendar_month_outlined,
          size: 18,
          color: NotionColors.ink,
        ),
      ),
      title: 'Lịch Giảng Dạy Tuần ${_calculateWeekNumber()}',
      subtitle:
          '${_classes.length} lớp học phần · Chọn một buổi học trên lịch để xem thông tin chi tiết và tiến hành điểm danh.',
      actions: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: NotionColors.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: NotionColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Tuần Trước',
                  onPressed: () => _changeWeek(-1),
                  icon: const Icon(Icons.chevron_left, size: 16, color: NotionColors.ink),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
                InkWell(
                  onTap: () => setState(() {
                    _weekStart = ScheduleOverview.startOfWeek(DateTime.now());
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'Hôm Nay',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: NotionColors.ink,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tuần Sau',
                  onPressed: () => _changeWeek(1),
                  icon: const Icon(Icons.chevron_right, size: 16, color: NotionColors.ink),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: NotionColors.ink,
              side: const BorderSide(color: NotionColors.hairline),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            onPressed: _isSyncingAttendance ? null : () => _syncFromGoogleSheet(),
            icon: _isSyncingAttendance
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: NotionColors.ink),
                  )
                : const Icon(Icons.sync, size: 14, color: NotionColors.ink),
            label: Text(
              _isSyncingAttendance ? 'Đang Đồng Bộ…' : 'Đồng Bộ Từ Google',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NotionColors.ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            onPressed: _isSaving ? null : _saveSchedules,
            child: Text(
              _isSaving ? 'Đang Lưu…' : 'Lưu Lịch Học',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Thao Tác Lịch',
            onSelected: (action) {
              switch (action) {
                case 'save':
                  _saveSchedules();
                case 'export':
                  _openExportDialogFromSchedule();
                case 'import':
                  AppNavigationController.instance.navigateToTab(2);
                case 'refresh':
                  _syncFromGoogleSheet();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'save',
                enabled: !_isSaving,
                child: Text(_isSaving ? 'Đang Lưu…' : 'Lưu Lịch Học'),
              ),
              const PopupMenuItem(value: 'export', child: Text('Xuất Báo Cáo')),
              const PopupMenuItem(value: 'import', child: Text('Nhập File Lớp')),
              PopupMenuItem(
                value: 'refresh',
                enabled: !_isSyncingAttendance,
                child: const Text('Làm Mới Điểm Danh'),
              ),
            ],
            icon: const Icon(Icons.more_horiz, size: 18, color: NotionColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _notionControlsBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEBEBEA),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_view_week_outlined,
                  size: 13,
                  color: NotionColors.ink,
                ),
                const SizedBox(width: 5),
                Text(
                  'Lịch Tuần',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: NotionColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 16, color: NotionColors.hairline),
          const SizedBox(width: 10),
          _filterChip(
            label: 'Tất cả (${_classes.length})',
            isSelected: _filter == _allClasses,
            onTap: () => setState(() => _filter = _allClasses),
          ),
          ..._classes.map((item) {
            final isSelected = _filter == item.sourceSheetName;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: InkWell(
                onTap: () => setState(() => _filter = item.sourceSheetName),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? NotionColors.ink : const Color(0xFFF7F7F5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? NotionColors.ink : NotionColors.hairline,
                    ),
                  ),
                  child: Text(
                    '${item.subjectCode} · ${item.classCode}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : NotionColors.ink,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
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
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? NotionColors.ink : const Color(0xFFF7F7F5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? NotionColors.ink : NotionColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : NotionColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _selectionPanel() {
    final selected = _selectedLesson;
    if (selected == null) {
      return const SizedBox.shrink();
    }
    final info = _getLessonAttendanceInfo(selected);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NotionColors.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, size) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bookmark_border_outlined,
                    size: 15,
                    color: NotionColors.ink,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${selected.importedClass.subjectCode} · ${selected.importedClass.classCode}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: NotionColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Buổi ${selected.lesson.sequenceNumber}/${selected.importedClass.lessonCount} · Slot ${selected.lesson.dailySlot} (${selected.lesson.startTime}–${selected.lesson.endTime}) · ${DateFormat('dd/MM/yyyy').format(selected.lesson.date)}'
                '${info.isAttended ? ' · Có mặt ${info.presentCount}/${info.totalCount}' : ''}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: NotionColors.inkSecondary,
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: NotionColors.surface,
                  foregroundColor: NotionColors.ink,
                  side: const BorderSide(color: NotionColors.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: _changeSelectedLessonDate,
                child: Text(
                  'Đổi Lịch',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: NotionColors.ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () => _openQrScreen(selected),
                child: Text(
                  'Mở điểm danh QR',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );

          if (size.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 10), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
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
        scheduleCode: c.scheduleCode,
        subjectCode: c.subjectCode,
        className: c.classCode,
        semester: c.semester,
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
        scheduleCode: initialOption.scheduleCode,
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

  double _calendarRowHeight = 112;

  Widget _weeklyTable() {
    final visibleSlots = _visibleSlots;
    final days = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: NotionColors.surface,
        borderRadius: NotionRounded.lg,
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: NotionElevation.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 560.0;
          _calendarRowHeight =
              ((availableHeight - 64) / visibleSlots.length.clamp(1, 5)).clamp(
                136.0,
                190.0,
              );
          final tableWidth = constraints.maxWidth < 1080
              ? 1080.0
              : constraints.maxWidth;
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            primary: false,
            child: SingleChildScrollView(
              primary: false,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Table(
                  border: const TableBorder(
                    horizontalInside: BorderSide(
                      color: NotionColors.hairline,
                      width: 1,
                    ),
                    verticalInside: BorderSide(
                      color: NotionColors.hairline,
                      width: 1,
                    ),
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
                      decoration: const BoxDecoration(color: NotionColors.canvasSoft),
                      children: [
                        const _HeaderCell(title: 'KHUNG GIỜ'),
                        ...List.generate(7, (index) {
                          final day = days[index];
                          final isToday =
                              day.year == now.year &&
                              day.month == now.month &&
                              day.day == now.day;
                          return _HeaderCell(
                            title: _dayNames[index],
                            subtitle: DateFormat('dd/MM').format(day),
                            isToday: isToday,
                          );
                        }),
                      ],
                    ),
                    ...visibleSlots.map((slot) {
                      final time = ScheduleCodeParser.slotTimes[slot]!;
                      return TableRow(
                        decoration: const BoxDecoration(
                          color: NotionColors.surface,
                        ),
                        children: [
                          Container(
                            constraints: BoxConstraints(
                              minHeight: _calendarRowHeight,
                            ),
                            color: NotionColors.canvasSoft,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Slot $slot',
                                  style: NotionTypography.eyebrow(
                                    color: _textPrimary,
                                  ).copyWith(fontSize: 12),
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
    final query = AppNavigationController.instance.searchQuery
        .trim()
        .toLowerCase();
    if (query.isNotEmpty) {
      lessons = lessons.where((item) {
        final sub = item.importedClass.subjectCode.toLowerCase();
        final cls = item.importedClass.classCode.toLowerCase();
        return sub.contains(query) || cls.contains(query);
      }).toList();
    }

    if (lessons.isEmpty) {
      return SizedBox(
        height: _calendarRowHeight,
        child: Center(
          child: Text(
            '—',
            style: TextStyle(color: Color(0xFFE3E2DE), fontSize: 13),
          ),
        ),
      );
    }

    final hasConflict = lessons.length > 1;

    return Container(
      constraints: BoxConstraints(minHeight: _calendarRowHeight),
      padding: const EdgeInsets.all(10),
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
    final attInfo = _getLessonAttendanceInfo(item);

    final borderColor = selected
        ? NotionColors.ink
        : (suggested
            ? NotionColors.inkSecondary
            : (attInfo.isAttended ? const Color(0xFFC4C4C2) : _borderColor));

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? const Color(0xFFF1F1EF)
            : (suggested
                  ? const Color(0xFFF7F7F5)
                  : (attInfo.isAttended
                        ? const Color(0xFFFAFAFA)
                        : NotionColors.surface)),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
          side: BorderSide(
            color: borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => _selectLesson(item),
          onDoubleTap: () {
            _selectLesson(item);
            _openQrScreen(item);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 7,
            ),
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
                          horizontal: 4,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: NotionColors.ink,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'Đang Diễn Ra',
                          style: GoogleFonts.inter(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),

                // Class code badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F1EF),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: NotionColors.hairline, width: 0.8),
                  ),
                  child: Text(
                    item.importedClass.classCode,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: NotionColors.ink,
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
                      horizontal: 4,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1EF),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: NotionColors.hairline,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check,
                          size: 10,
                          color: NotionColors.ink,
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
                              color: NotionColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isToday;

  const _HeaderCell({required this.title, this.subtitle, this.isToday = false});

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
                style: NotionTypography.eyebrow(
                  color: isToday ? NotionColors.ink : NotionColors.inkSecondary,
                ),
              ),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: NotionColors.ink,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Hôm Nay',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: NotionTypography.caption(
                color: NotionColors.inkMuted,
              ).copyWith(fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
