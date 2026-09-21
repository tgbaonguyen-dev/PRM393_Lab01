import 'dart:async';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/m1_snackbar.dart';
import '../../shared/notion_tokens.dart';
import '../../shared/workspace_ui.dart';
import '../../shell/app_shell.dart';
import '../attendance/services/attendance_storage_service.dart';
import '../export/export_report_service.dart';
import '../import/models/import_models.dart';
import '../schedule/services/schedule_api_client.dart';

enum ReportFormat { xlsx, csv }

class ReportsScreen extends StatefulWidget {
  final AttendanceStorageService? storageService;
  const ReportsScreen({super.key, this.storageService});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ExportReportService _exportService = ExportReportService();
  late final AttendanceStorageService _storageService =
      widget.storageService ?? AttendanceStorageService();
  String? _refreshError;
  final ScheduleApiClient _scheduleApiClient = ScheduleApiClient();
  final TextEditingController _studentSearchController =
      TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  List<ImportedClass> _classes = [];
  int _selectedClassIndex = 0;
  Map<String, Map<int, Map<String, String>>> _attendanceStore = {};
  final Set<int> _selectedSlots = {};
  ReportFormat _selectedFormat = ReportFormat.xlsx;

  bool _isSyncing = false;
  bool _isExporting = false;
  String _searchQuery = '';

  // 100% Exact Notion Tokens from ai/DESIGN.md
  static const _canvasBg = NotionColors.canvasSoft; // #F6F5F4
  static const _borderColor = NotionColors.hairline; // #E6E6E6
  static const _textPrimary = NotionColors.ink; // #000000
  static const _textSecondary = NotionColors.inkMuted; // #615D59
  static const _surfaceBg = NotionColors.surface; // #FFFFFF

  ImportedClass? get _currentClass {
    if (_classes.isEmpty || _selectedClassIndex >= _classes.length) return null;
    return _classes[_selectedClassIndex];
  }

  Map<int, Map<String, String>> _getClassAttendance(ImportedClass? cls) {
    if (cls == null) return {};
    return AttendanceStorageService.resolveClassAttendance(
      store: _attendanceStore,
      scheduleCode: cls.scheduleCode,
      subjectCode: cls.subjectCode,
      classCode: cls.classCode,
    );
  }

  @override
  void initState() {
    super.initState();
    final active = AppNavigationController.instance.activeClasses;
    if (active != null && active.isNotEmpty) {
      _classes = List.from(active);
      _resetSelectedSlots();
    }
    _loadInitialData();
    AppNavigationController.instance.addListener(_onNavigation);
  }

  @override
  void dispose() {
    AppNavigationController.instance.removeListener(_onNavigation);
    _studentSearchController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      // 1. Ưu tiên lấy danh sách lớp từ AppNavigationController hoặc tải local file
      List<ImportedClass> classes =
          AppNavigationController.instance.activeClasses ?? [];
      if (classes.isEmpty) {
        final local = _scheduleApiClient.loadLocalSchedules();
        if (local != null && local.classes.isNotEmpty) {
          classes = local.classes;
          AppNavigationController.instance.activeClasses = classes;
          AppNavigationController.instance.activeSchedules = local.schedules;
          AppNavigationController.instance.activeSemesterStart =
              local.firstLessonDate;
        } else {
          final saved = await _scheduleApiClient.loadSavedSchedules();
          if (saved.classes.isNotEmpty) {
            classes = saved.classes;
            AppNavigationController.instance.activeClasses = classes;
            AppNavigationController.instance.activeSchedules = saved.schedules;
            AppNavigationController.instance.activeSemesterStart =
                saved.firstLessonDate;
          }
        }
      }

      // 2. Lấy dữ liệu điểm danh từ Storage
      final store = await _storageService.loadStore();

      if (mounted) {
        setState(() {
          _classes = classes;
          _attendanceStore = store;
          _selectedClassIndex = _selectedClassIndex.clamp(
            0,
            (_classes.length - 1).clamp(0, 999),
          );
          if (_selectedSlots.isEmpty) _resetSelectedSlots();
        });
      }
    } catch (_) {}
    if (mounted && _classes.isNotEmpty) await _syncGoogleSheets();
  }

  void _onNavigation() {
    if (AppNavigationController.instance.currentIndex == 3) {
      unawaited(_loadInitialData());
    }
  }

  void _resetSelectedSlots() {
    final cls = _currentClass;
    _selectedSlots.clear();
    final count = (cls?.lessonCount ?? 20).clamp(1, 60);
    for (int i = 1; i <= count; i++) {
      _selectedSlots.add(i);
    }
  }

  void _selectAttendedSlotsOnly() {
    final cls = _currentClass;
    if (cls == null) return;
    final slotsMap = _getClassAttendance(cls);

    setState(() {
      _selectedSlots.clear();
      for (final slotNum in slotsMap.keys) {
        final studentStatuses = slotsMap[slotNum] ?? {};
        if (studentStatuses.isNotEmpty) {
          _selectedSlots.add(slotNum);
        }
      }
      if (_selectedSlots.isEmpty) {
        M1SnackBar.show(
          context,
          'Chưa có slot nào được ghi nhận điểm danh cho lớp này.',
          type: M1NoticeType.warning,
        );
        _resetSelectedSlots();
      }
    });
  }

  Future<void> _syncGoogleSheets({bool showToast = false}) async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _refreshError = null;
    });
    try {
      final fresh = await _storageService.fetchLatestStore();
      if (_classes.isEmpty) {
        try {
          final saved = await _scheduleApiClient.loadSavedSchedules();
          if (saved.classes.isNotEmpty && mounted) {
            setState(() {
              _classes = saved.classes;
              _selectedClassIndex =
                  _selectedClassIndex.clamp(0, (_classes.length - 1).clamp(0, 999));
            });
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _attendanceStore = fresh;
          _refreshError = null;
        });
        if (showToast) {
          M1SnackBar.show(
            context,
            'Đã đồng bộ dữ liệu mới nhất từ Google Sheet.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _refreshError =
              'Chưa lấy được dữ liệu mới nhất. Bảng đang hiển thị bản lưu trên máy.',
        );
        if (showToast) {
          M1SnackBar.show(
            context,
            'Không thể kết nối với Google Sheet để đồng bộ.',
            type: M1NoticeType.warning,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _exportReport() async {
    final cls = _currentClass;
    if (cls == null) return;

    if (_selectedSlots.isEmpty) {
      M1SnackBar.show(
        context,
        'Vui lòng chọn ít nhất một buổi học (Slot) để xuất báo cáo.',
        type: M1NoticeType.warning,
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final ext = _selectedFormat == ReportFormat.xlsx ? 'xlsx' : 'csv';
      final sortedSlots = _selectedSlots.toList()..sort();
      final slotsLabel = sortedSlots.length == cls.lessonCount
          ? 'All${sortedSlots.length}Slots'
          : 'Slots_${sortedSlots.join('_')}';

      final defaultFileName =
          '${cls.subjectCode}_${cls.classCode}_${cls.semester}_$slotsLabel.$ext';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Chọn nơi lưu file báo cáo điểm danh',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: [ext],
      );

      if (savePath == null) {
        if (mounted) setState(() => _isExporting = false);
        return;
      }

      final fresh = await _storageService.fetchLatestStore();
      if (!mounted) return;
      setState(() {
        _attendanceStore = fresh;
        _refreshError = null;
      });

      final finalPath = savePath.endsWith('.$ext')
          ? savePath
          : '$savePath.$ext';

      final rosterList = cls.students
          .map(
            (s) => {
              'rollNumber': s.rollNumber,
              'fullName': s.fullName,
              'email': s.email,
              'memberCode': s.memberCode,
              'classCode': s.classCode,
            },
          )
          .toList();

      final classAttendance = _getClassAttendance(cls);

      // Chuyển attendance data thành map email -> {slot: status}
      final Map<String, Map<int, String>> attendanceMap = {};
      for (final student in cls.students) {
        final email = student.email.trim().toLowerCase();
        attendanceMap[email] = {};
        for (final slot in sortedSlots) {
          final slotData = classAttendance[slot] ?? {};
          final status = slotData[email] ?? '';
          if (status.isNotEmpty) {
            attendanceMap[email]![slot] = status;
          }
        }
      }

      // Map lessonDates
      final Map<int, String> lessonDates = {};
      final activeSchedules = AppNavigationController.instance.activeSchedules;
      if (activeSchedules != null &&
          activeSchedules.containsKey(cls.sourceSheetName)) {
        for (final lesson in activeSchedules[cls.sourceSheetName]!) {
          lessonDates[lesson.sequenceNumber] =
              '${lesson.date.day.toString().padLeft(2, '0')}/${lesson.date.month.toString().padLeft(2, '0')}';
        }
      }

      late final ExportResult result;
      if (_selectedFormat == ReportFormat.xlsx) {
        result = await _exportService.exportToExcel(
          subjectCode: cls.subjectCode,
          className: cls.classCode,
          semester: cls.semester,
          roster: rosterList,
          selectedLessonNumbers: sortedSlots,
          lessonDates: lessonDates,
          attendanceData: attendanceMap,
          targetFilePath: finalPath,
        );
      } else {
        result = await _exportService.exportToCsv(
          subjectCode: cls.subjectCode,
          className: cls.classCode,
          roster: rosterList,
          selectedLessonNumbers: sortedSlots,
          lessonDates: lessonDates,
          attendanceData: attendanceMap,
          targetFilePath: finalPath,
        );
      }

      if (!mounted) return;

      if (result.success) {
        M1SnackBar.show(
          context,
          'Xuất báo cáo thành công: ${cls.classCode} (${result.studentCount} sinh viên, ${result.lessonCount} slot)',
          type: M1NoticeType.success,
        );
      } else {
        M1SnackBar.show(
          context,
          'Xuất báo cáo thất bại: ${result.error ?? "Lỗi không xác định"}',
          type: M1NoticeType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        M1SnackBar.show(
          context,
          'Lỗi khi xuất báo cáo: $e',
          type: M1NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_classes.isEmpty) {
      return _buildEmptyState();
    }

    final cls = _currentClass!;
    final classAttendance = _getClassAttendance(cls);
    final sortedSlots = _selectedSlots.toList()..sort();

    // Tính toán số liệu thống kê
    int totalSlotsEvaluated = sortedSlots.length;
    int totalPresents = 0;
    int totalAbsents = 0;
    int atRiskStudentsCount = 0;

    final query = _searchQuery.trim().toLowerCase();
    final filteredStudents = query.isEmpty
        ? cls.students
        : cls.students.where((s) {
            return s.rollNumber.toLowerCase().contains(query) ||
                s.fullName.toLowerCase().contains(query) ||
                s.email.toLowerCase().contains(query) ||
                s.memberCode.toLowerCase().contains(query);
          }).toList();

    for (final student in cls.students) {
      final email = student.email.trim().toLowerCase();
      int studentAbsent = 0;
      for (final slot in sortedSlots) {
        final st = (classAttendance[slot]?[email] ?? '').toUpperCase();
        if (st == 'P') totalPresents++;
        if (st == 'A') {
          totalAbsents++;
          studentAbsent++;
        }
      }
      final absentRate = totalSlotsEvaluated > 0
          ? (studentAbsent / totalSlotsEvaluated) * 100
          : 0.0;
      if (absentRate > 20.0) {
        atRiskStudentsCount++;
      }
    }

    final totalEntries = totalPresents + totalAbsents;
    final presentPct = totalEntries > 0
        ? ((totalPresents / totalEntries) * 100).toStringAsFixed(1)
        : '100.0';
    final absentPct = totalEntries > 0
        ? ((totalAbsents / totalEntries) * 100).toStringAsFixed(1)
        : '0.0';

    return Scaffold(
      backgroundColor: _canvasBg,
      body: WorkspacePage(
        header: [
          _buildHeader(),
          if (_refreshError != null)
            Text(
              _refreshError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB87214)),
            ),
          IgnorePointer(
            ignoring: _isExporting,
            child: _buildFilterControls(cls),
          ),
          _buildSummaryCards(
            totalStudents: cls.students.length,
            selectedSlotsCount: sortedSlots.length,
            presentPct: presentPct,
            absentPct: absentPct,
            atRiskCount: atRiskStudentsCount,
          ),
        ],
        body: _buildPreviewTable(
          students: filteredStudents,
          totalStudentsCount: cls.students.length,
          sortedSlots: sortedSlots,
          classAttendance: classAttendance,
        ),
      ),
    );
  }

  Widget _buildHeader() => WorkspaceHeader(
    icon: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1EF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.insights_outlined,
        size: 18,
        color: NotionColors.ink,
      ),
    ),
    title: 'Báo Cáo & Thống Kê Điểm Danh',
    subtitle: _isSyncing
        ? 'Đang cập nhật điểm danh…'
        : 'Dữ liệu tự cập nhật khi mở báo cáo và trước mỗi lần xuất file.',
    actions: Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: NotionColors.ink,
            side: const BorderSide(color: NotionColors.hairline),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 36),
          ),
          onPressed: _isSyncing ? null : () => _syncGoogleSheets(showToast: true),
          icon: _isSyncing
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: NotionColors.ink),
                )
              : const Icon(Icons.sync, size: 14, color: NotionColors.ink),
          label: Text(
            _isSyncing ? 'Đang Đồng Bộ…' : 'Đồng Bộ Từ Google',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: NotionColors.ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          onPressed: _isExporting || _isSyncing ? null : _exportReport,
          child: Text(
            _isExporting ? 'Đang Xuất…' : 'Xuất Báo Cáo',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _buildFilterControls(ImportedClass currentClass) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 380,
            child: DropdownButtonFormField<int>(
              initialValue: _selectedClassIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Lớp Học Phần',
              ),
              items: List.generate(
                _classes.length,
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text(
                    '${_classes[i].subjectCode} — ${_classes[i].classCode}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              onChanged: (i) {
                if (i != null) {
                  setState(() {
                    _selectedClassIndex = i;
                    _resetSelectedSlots();
                  });
                }
              },
            ),
          ),
          _buildFormatSelector(),
          Container(
            decoration: BoxDecoration(
              color: NotionColors.canvasSoft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: PopupMenuButton<String>(
              tooltip: 'Chọn Buổi Xuất',
              onSelected: (v) {
                if (v == 'all') setState(_resetSelectedSlots);
                if (v == 'attended') _selectAttendedSlotsOnly();
                if (v == 'none') setState(_selectedSlots.clear);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Tất Cả Buổi Học')),
                PopupMenuItem(
                  value: 'attended',
                  child: Text('Chỉ Buổi Đã Điểm Danh'),
                ),
                PopupMenuItem(value: 'none', child: Text('Bỏ Chọn Tất Cả')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Chọn Nhanh Buổi ▾',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: NotionColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: NotionColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderColor, width: 1),
          boxShadow: NotionElevation.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'CHỌN BUỔI BÁO CÁO (${_selectedSlots.length}/${currentClass.lessonCount})',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: _textSecondary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(_resetSelectedSlots),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Tất cả',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: NotionColors.ink,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _selectAttendedSlotsOnly,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Đã điểm danh',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: NotionColors.ink,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(_selectedSlots.clear),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Bỏ chọn',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _textSecondary,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(currentClass.lessonCount.clamp(1, 60), (i) {
                final n = i + 1;
                final selected = _selectedSlots.contains(n);
                return InkWell(
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedSlots.remove(n);
                    } else {
                      _selectedSlots.add(n);
                    }
                  }),
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 38,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? NotionColors.ink : const Color(0xFFF7F7F5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? NotionColors.ink : _borderColor,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$n',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? Colors.white : _textPrimary,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildFormatSelector() {
    return Container(
      decoration: BoxDecoration(
        color: NotionColors.canvasSoft,
        borderRadius: NotionRounded.sm,
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _formatChip(ReportFormat.xlsx, 'Excel (.xlsx)'),
          _formatChip(ReportFormat.csv, 'CSV (.csv)'),
        ],
      ),
    );
  }

  Widget _formatChip(ReportFormat format, String label) {
    final isSelected = _selectedFormat == format;
    return InkWell(
      onTap: () {
        if (!isSelected) {
          setState(() => _selectedFormat = format);
        }
      },
      borderRadius: NotionRounded.xs,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? NotionColors.surface : Colors.transparent,
          borderRadius: NotionRounded.xs,
          boxShadow: isSelected ? NotionElevation.soft : null,
        ),
        child: Text(
          label,
          style: NotionTypography.eyebrow(
            color: isSelected ? _textPrimary : _textSecondary,
          ).copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards({
    required int totalStudents,
    required int selectedSlotsCount,
    required String presentPct,
    required String absentPct,
    required int atRiskCount,
  }) {
    return LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth >= 1050
            ? 5
            : size.maxWidth >= 650
            ? 3
            : 2;
        final width = (size.maxWidth - (columns - 1) * 12) / columns;
        final cards = [
          _metricCard(
            title: 'SĨ SỐ LỚP',
            value: '$totalStudents SV',
            subtitle: 'Học kỳ ${_currentClass?.semester ?? ""}',
            icon: Icons.people_outline,
            accentColor: _textPrimary,
          ),
          _metricCard(
            title: 'SLOT ĐÃ CHỌN',
            value: '$selectedSlotsCount buổi',
            subtitle: 'Trên ${_currentClass?.lessonCount ?? 20} buổi',
            icon: Icons.event_outlined,
            accentColor: _textPrimary,
          ),
          _metricCard(
            title: 'TỈ LỆ CÓ MẶT',
            value: '$presentPct%',
            subtitle: 'Kết quả đã ghi nhận',
            icon: Icons.check,
            accentColor: const Color(0xFF1F7A4D),
          ),
          _metricCard(
            title: 'TỈ LỆ VẮNG',
            value: '$absentPct%',
            subtitle: 'Kết quả đã ghi nhận',
            icon: Icons.remove,
            accentColor: const Color(0xFFB87214),
          ),
          _metricCard(
            title: 'NGUY CƠ (>20%)',
            value: '$atRiskCount SV',
            subtitle: 'Cần theo dõi',
            icon: Icons.flag_outlined,
            accentColor: _textPrimary,
          ),
        ];
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceBg,
        borderRadius: NotionRounded.md,
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: NotionElevation.soft,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NotionTypography.eyebrow(color: _textSecondary),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: NotionTypography.heading3(color: _textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: NotionTypography.caption(color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewTable({
    required List<ImportedStudent> students,
    required int totalStudentsCount,
    required List<int> sortedSlots,
    required Map<int, Map<String, String>> classAttendance,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceBg,
        borderRadius: NotionRounded.md,
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: NotionElevation.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header preview table with search
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 20,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Bảng Điểm Danh · ${students.length}/$totalStudentsCount Sinh Viên',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(
                  width: 380,
                  child: WorkspaceSearch(
                    controller: _studentSearchController,
                    hint: 'Tìm kiếm MSSV, tên, email...',
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _borderColor),

          // The Data Table
          Expanded(
            child: students.isEmpty
                ? Center(
                    child: Text(
                      'Không tìm thấy sinh viên phù hợp với từ khóa "$_searchQuery"',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _textSecondary,
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(5),
                      bottomRight: Radius.circular(5),
                    ),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        notificationPredicate: (notif) =>
                            notif.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Scrollbar(
                            controller: _verticalScrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            notificationPredicate: (notif) =>
                                notif.metrics.axis == Axis.vertical,
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  const Color(0xFFF7F6F3),
                                ),
                                headingRowHeight: 44,
                                dataRowMinHeight: 46,
                                dataRowMaxHeight: 46,
                                columnSpacing: 20,
                                horizontalMargin: 18,
                                dividerThickness: 0.5,
                                columns: [
                                  DataColumn(label: _th('STT')),
                                  DataColumn(label: _th('MSSV')),
                                  DataColumn(label: _th('Họ và tên')),
                                  DataColumn(label: _th('Email')),
                                  ...sortedSlots.map(
                                    (s) => DataColumn(
                                      label: _th('S$s'),
                                    ),
                                  ),
                                  DataColumn(label: _th('Vắng (A)')),
                                  DataColumn(label: _th('Có mặt (P)')),
                                  DataColumn(label: _th('Tỉ lệ vắng')),
                                  DataColumn(label: _th('Trạng thái')),
                                ],
                                rows: List.generate(students.length, (idx) {
                                  final student = students[idx];
                                  final email = student.email
                                      .trim()
                                      .toLowerCase();

                                  int absentCount = 0;
                                  int presentCount = 0;

                                  final slotCells = sortedSlots.map((slot) {
                                    final status =
                                        (classAttendance[slot]?[email] ?? '')
                                            .toUpperCase();
                                    if (status == 'P') {
                                      presentCount++;
                                      return DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: NotionColors.tagGreenBg,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: NotionColors.hairline,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            'P',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: NotionColors.tagGreenText,
                                            ),
                                          ),
                                        ),
                                      );
                                    } else if (status == 'A') {
                                      absentCount++;
                                      return DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: NotionColors.tagAmberBg,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: NotionColors.hairline,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            'A',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: NotionColors.tagAmberText,
                                            ),
                                          ),
                                        ),
                                      );
                                    } else {
                                      return DataCell(
                                        Text(
                                          '—',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: const Color(0xFFD1D5DB),
                                          ),
                                        ),
                                      );
                                    }
                                  }).toList();

                                  final totalSlots = sortedSlots.length;
                                  final absentRate = totalSlots > 0
                                      ? (absentCount / totalSlots) * 100
                                      : 0.0;
                                  final isAtRisk = absentRate > 20.0;

                                  return DataRow(
                                    color: isAtRisk
                                        ? WidgetStateProperty.all(
                                            const Color(0xFFFEF2F2),
                                          )
                                        : null,
                                    cells: [
                                      DataCell(
                                        Text(
                                          '${idx + 1}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _cellStyle(isSecondary: true),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          student.rollNumber,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimary,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          student.fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          style: _cellStyle(),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          student.email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          style: _cellStyle(isSecondary: true),
                                        ),
                                      ),
                                      ...slotCells,
                                      DataCell(
                                        Text(
                                          '$absentCount',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: absentCount > 0
                                                ? const Color(0xFFDC2626)
                                                : _textSecondary,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '$presentCount',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF16A34A),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${absentRate.toStringAsFixed(1)}%',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: isAtRisk
                                                ? const Color(0xFFDC2626)
                                                : _textPrimary,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isAtRisk
                                                ? const Color(0xFFFEE2E2)
                                                : const Color(0xFFF1F1EF),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(
                                              color: isAtRisk
                                                  ? const Color(0xFFFECACA)
                                                  : NotionColors.hairline,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            isAtRisk
                                                ? 'Nguy cơ cấm thi'
                                                : 'Bình thường',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isAtRisk
                                                  ? const Color(0xFFDC2626)
                                                  : _textSecondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _th(String label) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _textSecondary,
      ),
    );
  }

  TextStyle _cellStyle({bool isSecondary = false}) {
    return GoogleFonts.inter(
      fontSize: 12.5,
      color: isSecondary ? _textSecondary : _textPrimary,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bar_chart_outlined,
              size: 36,
              color: _textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Chưa Có Dữ Liệu Báo Cáo',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Vui lòng nạp danh sách lớp hoặc tải lịch đã lưu trước khi xuất báo cáo.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12.5, color: _textSecondary),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _textPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onPressed: () =>
                  AppNavigationController.instance.navigateToTab(2),
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Nhập Danh Sách Lớp'),
            ),
          ],
        ),
      ),
    );
  }
}
