import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/m1_snackbar.dart';
import '../../shell/app_shell.dart';
import '../attendance/services/attendance_storage_service.dart';
import '../export/export_report_service.dart';
import '../import/models/import_models.dart';
import '../schedule/services/schedule_api_client.dart';

enum ReportFormat { xlsx, csv }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ExportReportService _exportService = ExportReportService();
  final AttendanceStorageService _storageService = AttendanceStorageService();
  final ScheduleApiClient _scheduleApiClient = ScheduleApiClient();
  final TextEditingController _studentSearchController = TextEditingController();

  List<ImportedClass> _classes = [];
  int _selectedClassIndex = 0;
  Map<String, Map<int, Map<String, String>>> _attendanceStore = {};
  final Set<int> _selectedSlots = {};
  ReportFormat _selectedFormat = ReportFormat.xlsx;

  bool _isLoading = false;
  bool _isSyncing = false;
  bool _isExporting = false;
  String _searchQuery = '';

  // Notion Academic Minimalist Palette
  static const _canvasBg = Color(0xFFFAF9F6);
  static const _borderColor = Color(0xFFE3E2DE);
  static const _textPrimary = Color(0xFF37352F);
  static const _textSecondary = Color(0xFF787774);
  static const _surfaceBg = Colors.white;

  ImportedClass? get _currentClass {
    if (_classes.isEmpty || _selectedClassIndex >= _classes.length) return null;
    return _classes[_selectedClassIndex];
  }

  String get _currentClassKey {
    final cls = _currentClass;
    if (cls == null) return '';
    return '${cls.scheduleCode}_${cls.subjectCode}_${cls.classCode}';
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
  }

  @override
  void dispose() {
    _studentSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      // 1. Ưu tiên lấy danh sách lớp từ AppNavigationController hoặc tải local file
      List<ImportedClass> classes = AppNavigationController.instance.activeClasses ?? [];
      if (classes.isEmpty) {
        final local = _scheduleApiClient.loadLocalSchedules();
        if (local != null && local.classes.isNotEmpty) {
          classes = local.classes;
          AppNavigationController.instance.activeClasses = classes;
          AppNavigationController.instance.activeSchedules = local.schedules;
          AppNavigationController.instance.activeSemesterStart = local.firstLessonDate;
        } else {
          final saved = await _scheduleApiClient.loadSavedSchedules();
          if (saved.classes.isNotEmpty) {
            classes = saved.classes;
            AppNavigationController.instance.activeClasses = classes;
            AppNavigationController.instance.activeSchedules = saved.schedules;
            AppNavigationController.instance.activeSemesterStart = saved.firstLessonDate;
          }
        }
      }

      // 2. Lấy dữ liệu điểm danh từ Storage
      final store = await _storageService.loadStore();

      if (mounted) {
        setState(() {
          _classes = classes;
          _attendanceStore = store;
          _selectedClassIndex = 0;
          _resetSelectedSlots();
        });
      }
    } catch (_) {}
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

  Future<void> _syncGoogleSheets() async {
    setState(() => _isSyncing = true);
    try {
      final success = await _storageService.pullFromRemote();
      if (!mounted) return;
      if (success) {
        final freshStore = await _storageService.loadStore();
        setState(() {
          _attendanceStore = freshStore;
        });
        M1SnackBar.show(
          context,
          'Đã đồng bộ dữ liệu điểm danh mới nhất từ Google Sheets thành công!',
          type: M1NoticeType.success,
        );
      } else {
        M1SnackBar.show(
          context,
          'Không thể kết nối đến Google Sheets. Hãy kiểm tra kết nối mạng và backend.',
          type: M1NoticeType.warning,
        );
      }
    } catch (e) {
      if (mounted) {
        M1SnackBar.show(
          context,
          'Lỗi khi đồng bộ: $e',
          type: M1NoticeType.error,
        );
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

      final defaultFileName = '${cls.subjectCode}_${cls.classCode}_${cls.semester}_$slotsLabel.$ext';

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

      final finalPath = savePath.endsWith('.$ext') ? savePath : '$savePath.$ext';

      final rosterList = cls.students
          .map((s) => {
                'rollNumber': s.rollNumber,
                'fullName': s.fullName,
                'email': s.email,
                'memberCode': s.memberCode,
                'classCode': s.classCode,
              })
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
      if (activeSchedules != null && activeSchedules.containsKey(cls.classCode)) {
        for (final lesson in activeSchedules[cls.classCode]!) {
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
      final absentRate = totalSlotsEvaluated > 0 ? (studentAbsent / totalSlotsEvaluated) * 100 : 0.0;
      if (absentRate > 20.0) {
        atRiskStudentsCount++;
      }
    }

    final totalEntries = totalPresents + totalAbsents;
    final presentPct = totalEntries > 0 ? ((totalPresents / totalEntries) * 100).toStringAsFixed(1) : '100.0';
    final absentPct = totalEntries > 0 ? ((totalAbsents / totalEntries) * 100).toStringAsFixed(1) : '0.0';

    return Scaffold(
      backgroundColor: _canvasBg,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Thanh tiêu đề & Các nút hành động chính
            _buildHeader(),
            const SizedBox(height: 14),

            // 2. Khung điều khiển: Chọn Lớp, Chọn Slot, Định dạng Xuất
            _buildFilterControls(cls),
            const SizedBox(height: 14),

            // 3. Thẻ tóm tắt chỉ số thống kê (Summary Cards)
            _buildSummaryCards(
              totalStudents: cls.students.length,
              selectedSlotsCount: sortedSlots.length,
              presentPct: presentPct,
              absentPct: absentPct,
              atRiskCount: atRiskStudentsCount,
            ),
            const SizedBox(height: 14),

            // 4. Bảng xem trước dữ liệu điểm danh
            Expanded(
              child: _buildPreviewTable(
                students: filteredStudents,
                totalStudentsCount: cls.students.length,
                sortedSlots: sortedSlots,
                classAttendance: classAttendance,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderColor, width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.assessment_outlined,
              size: 20,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Báo Cáo & Thống Kê Điểm Danh',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tổng hợp dữ liệu điểm danh, theo dõi sinh viên có nguy cơ cấm thi và xuất file Excel / CSV',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Nút Đồng bộ Google Sheet
          InkWell(
            onTap: _isSyncing ? null : _syncGoogleSheets,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSyncing)
                    const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: _textSecondary),
                    )
                  else
                    const Icon(Icons.cloud_sync_outlined, size: 15, color: _textPrimary),
                  const SizedBox(width: 6),
                  Text(
                    _isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ Google Sheet',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Nút Xuất Báo Cáo
          InkWell(
            onTap: _isExporting ? null : _exportReport,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _textPrimary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isExporting)
                    const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
                    )
                  else
                    const Icon(Icons.download_outlined, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    _isExporting ? 'Đang xuất file...' : 'Xuất Báo Cáo (${_selectedFormat.name.toUpperCase()})',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls(ImportedClass currentClass) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Chọn Lớp Học
                Text(
                  'Chọn lớp:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6F3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedClassIndex,
                      dropdownColor: Colors.white,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                      items: List.generate(_classes.length, (idx) {
                        final c = _classes[idx];
                        return DropdownMenuItem<int>(
                          value: idx,
                          child: Text(
                            '${c.subjectCode} — ${c.classCode} (${c.students.length} SV)',
                          ),
                        );
                      }),
                      onChanged: (idx) {
                        if (idx != null && idx != _selectedClassIndex) {
                          setState(() {
                            _selectedClassIndex = idx;
                            _resetSelectedSlots();
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // 2. Định dạng Xuất (XLSX / CSV)
                Text(
                  'Định dạng:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                _buildFormatSelector(),

                const SizedBox(width: 24),

                // Quick Slot Actions
                TextButton(
                  onPressed: () {
                    setState(() => _resetSelectedSlots());
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    'Chọn tất cả slot',
                    style: GoogleFonts.inter(fontSize: 11.5, color: _textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: _selectAttendedSlotsOnly,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    'Chỉ slot đã điểm danh',
                    style: GoogleFonts.inter(fontSize: 11.5, color: _textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedSlots.clear());
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: Text(
                    'Bỏ chọn',
                    style: GoogleFonts.inter(fontSize: 11.5, color: _textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: _borderColor),
          const SizedBox(height: 10),

          // Horizontal Slot Selector Pills
          Row(
            children: [
              Text(
                'Slot xuất:',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(
                      currentClass.lessonCount.clamp(1, 60),
                      (index) {
                        final slotNum = index + 1;
                        final isSelected = _selectedSlots.contains(slotNum);
                        final hasAttendance =
                            (_getClassAttendance(currentClass)[slotNum]?.isNotEmpty ?? false);

                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedSlots.remove(slotNum);
                                } else {
                                  _selectedSlots.add(slotNum);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _textPrimary
                                    : const Color(0xFFF7F6F3),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected ? _textPrimary : _borderColor,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Slot $slotNum',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                      color: isSelected ? Colors.white : _textPrimary,
                                    ),
                                  ),
                                  if (hasAttendance) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF86EFAC) : const Color(0xFF16A34A),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6F3),
        borderRadius: BorderRadius.circular(4),
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
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          boxShadow: isSelected
              ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? _textPrimary : _textSecondary,
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
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'SĨ SỐ LỚP',
            value: '$totalStudents SV',
            subtitle: 'Học kỳ ${_currentClass?.semester ?? "FA26"}',
            icon: Icons.people_outline,
            accentColor: _textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: 'SLOT ĐÃ CHỌN',
            value: '$selectedSlotsCount buổi',
            subtitle: 'Trên tổng ${_currentClass?.lessonCount ?? 20} slot',
            icon: Icons.event_available_outlined,
            accentColor: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: 'TỈ LỆ CÓ MẶT',
            value: '$presentPct%',
            subtitle: 'Trạng thái tích cực',
            icon: Icons.check_circle_outline,
            accentColor: const Color(0xFF16A34A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: 'TỈ LỆ VẮNG',
            value: '$absentPct%',
            subtitle: 'Trung bình các buổi',
            icon: Icons.cancel_outlined,
            accentColor: const Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: 'NGUY CƠ CẤM THI (>20%)',
            value: '$atRiskCount SV',
            subtitle: atRiskCount > 0 ? 'Cần cảnh báo sinh viên' : 'Lớp chuyên cần tốt',
            icon: Icons.warning_amber_rounded,
            accentColor: atRiskCount > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
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
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header preview table with search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Xem Trước Bảng Điểm Danh (${students.length}/$totalStudentsCount SV)',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                // Search Input Box
                Container(
                  width: 260,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6F3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 15, color: _textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _studentSearchController,
                          onChanged: (val) {
                            setState(() => _searchQuery = val);
                          },
                          style: GoogleFonts.inter(fontSize: 12, color: _textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Tìm kiếm MSSV, tên, email...',
                            hintStyle: TextStyle(fontSize: 11.5, color: _textSecondary),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        InkWell(
                          onTap: () {
                            _studentSearchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.close, size: 14, color: _textSecondary),
                        ),
                    ],
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
                      style: GoogleFonts.inter(fontSize: 12.5, color: _textSecondary),
                    ),
                  )
                : ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(5),
                      bottomRight: Radius.circular(5),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F6F3)),
                          headingRowHeight: 36,
                          dataRowMinHeight: 34,
                          dataRowMaxHeight: 34,
                          dividerThickness: 0.8,
                          columns: [
                            DataColumn(label: _th('STT')),
                            DataColumn(label: _th('MSSV')),
                            DataColumn(label: _th('Họ và tên')),
                            DataColumn(label: _th('Email')),
                            ...sortedSlots.map((s) => DataColumn(label: _th('S$s'))),
                            DataColumn(label: _th('Vắng (A)')),
                            DataColumn(label: _th('Có mặt (P)')),
                            DataColumn(label: _th('Tỉ lệ vắng')),
                            DataColumn(label: _th('Trạng thái')),
                          ],
                          rows: List.generate(students.length, (idx) {
                            final student = students[idx];
                            final email = student.email.trim().toLowerCase();

                            int absentCount = 0;
                            int presentCount = 0;

                            final slotCells = sortedSlots.map((slot) {
                              final status = (classAttendance[slot]?[email] ?? '').toUpperCase();
                              if (status == 'P') {
                                presentCount++;
                                return DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'P',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF16A34A),
                                      ),
                                    ),
                                  ),
                                );
                              } else if (status == 'A') {
                                absentCount++;
                                return DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'A',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ),
                                );
                              } else {
                                return DataCell(
                                  Text(
                                    '—',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: const Color(0xFFD1D5DB),
                                    ),
                                  ),
                                );
                              }
                            }).toList();

                            final totalSlots = sortedSlots.length;
                            final absentRate = totalSlots > 0 ? (absentCount / totalSlots) * 100 : 0.0;
                            final isAtRisk = absentRate > 20.0;

                            return DataRow(
                              color: isAtRisk
                                  ? WidgetStateProperty.all(const Color(0xFFFEF2F2))
                                  : null,
                              cells: [
                                DataCell(Text('${idx + 1}', style: _cellStyle(isSecondary: true))),
                                DataCell(
                                  Text(
                                    student.rollNumber,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ),
                                DataCell(Text(student.fullName, style: _cellStyle())),
                                DataCell(Text(student.email, style: _cellStyle(isSecondary: true))),
                                ...slotCells,
                                DataCell(
                                  Text(
                                    '$absentCount',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: absentCount > 0 ? const Color(0xFFDC2626) : _textSecondary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '$presentCount',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    '${absentRate.toStringAsFixed(1)}%',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: isAtRisk ? const Color(0xFFDC2626) : _textPrimary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isAtRisk ? const Color(0xFFFEE2E2) : const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      isAtRisk ? 'Nguy cơ cấm thi' : 'Bình thường',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: isAtRisk ? const Color(0xFFDC2626) : _textSecondary,
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
        ],
      ),
    );
  }

  Widget _th(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: _textSecondary,
      ),
    );
  }

  TextStyle _cellStyle({bool isSecondary = false}) {
    return GoogleFonts.inter(
      fontSize: 11.5,
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
            const Icon(Icons.bar_chart_outlined, size: 36, color: _textSecondary),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => AppNavigationController.instance.navigateToTab(2),
              icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Nhập Danh Sách Lớp'),
            ),
          ],
        ),
      ),
    );
  }
}
