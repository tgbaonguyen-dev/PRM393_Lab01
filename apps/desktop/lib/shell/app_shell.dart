import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../features/attendance/services/attendance_storage_service.dart';
import '../features/settings/app_reset_dialog.dart';
import '../features/import/import_screen.dart';
import '../features/import/models/import_models.dart';
import '../features/reports/reports_screen.dart';
import '../features/schedule/models/schedule_models.dart';
import '../features/schedule/schedule_generator_screen.dart';
import '../features/schedule/services/schedule_api_client.dart';
import '../features/session/qr_display_screen.dart';
import '../shared/notion_tokens.dart';

/// Bộ điều khiển điều hướng tập trung của EduCheck Pro
class AppNavigationController extends ChangeNotifier {
  static final AppNavigationController instance = AppNavigationController._();
  AppNavigationController._();

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  // Dữ liệu học vụ dùng chung giữa các tab
  List<ImportedClass>? activeClasses;
  Map<String, List<ClassLesson>>? activeSchedules;
  DateTime? activeSemesterStart;

  // Phiên điểm danh QR / Giám sát hiện hành
  String? activeSessionId;
  String? activeClassId;
  String? activeClassName;
  String? activeLessonLabel;
  List<Map<String, dynamic>>? activeRoster;

  // Bộ lọc hiển thị (Lý Thuyết / Thực Hành / Họp Bộ Môn)
  bool showTheory = true;
  bool showPractice = true;
  bool showMeetings = true;
  String searchQuery = '';

  bool resetting = false;
  void setResetting(bool value) {
    resetting = value;
    notifyListeners();
  }

  int workspaceVersion = 0;
  void clearWorkspace() {
    activeClasses = null;
    activeSchedules = null;
    activeSemesterStart = null;
    activeSessionId = null;
    activeClassId = null;
    activeClassName = null;
    activeLessonLabel = null;
    activeRoster = null;
    searchQuery = '';
    _currentIndex = 0;
    _scheduleVersion++;
    workspaceVersion++;
    notifyListeners();
  }

  void navigateToTab(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  int _scheduleVersion = 0;
  int get scheduleVersion => _scheduleVersion;

  void openScheduleWithClasses({
    required List<ImportedClass> classes,
    Map<String, List<ClassLesson>>? schedules,
    DateTime? semesterStart,
  }) {
    activeClasses = classes;
    activeSchedules = schedules;
    activeSemesterStart = semesterStart;
    _scheduleVersion++;
    _currentIndex = 0; // Tab Lịch Giảng Dạy
    notifyListeners();
  }

  void openQrForSession({
    required String sessionId,
    required String classId,
    required String className,
    required String lessonLabel,
    List<Map<String, dynamic>>? roster,
  }) {
    activeSessionId = sessionId;
    activeClassId = classId;
    activeClassName = className;
    activeLessonLabel = lessonLabel;
    activeRoster = roster;
    _currentIndex = 1; // Tab Điểm Danh QR
    notifyListeners();
  }

  void toggleFilter({bool? theory, bool? practice, bool? meetings}) {
    if (theory != null) showTheory = theory;
    if (practice != null) showPractice = practice;
    if (meetings != null) showMeetings = meetings;
    notifyListeners();
  }

  void updateSearch(String query) {
    searchQuery = query;
    notifyListeners();
  }
}

class AppShell extends StatefulWidget {
  final bool loadExistingData;
  final AttendanceStorageService? storageService;
  const AppShell({
    super.key,
    this.loadExistingData = true,
    this.storageService,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppNavigationController _nav = AppNavigationController.instance;
  final ScheduleApiClient _scheduleApiClient = ScheduleApiClient();

  bool _backendOnline = false;
  Timer? _backendCheckTimer;

  static const _borderColor = NotionColors.hairline;
  static const _textPrimary = NotionColors.ink;
  static const _textSecondary = NotionColors.inkMuted;

  @override
  void initState() {
    super.initState();
    _nav.addListener(_onNavChanged);
    if (!widget.loadExistingData) return;
    _tryLoadLocalSchedulesSync();
    _checkBackendHealth();
    _backendCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkBackendHealth(),
    );
    _loadInitialSavedSchedule();
  }

  @override
  void dispose() {
    _nav.removeListener(_onNavChanged);
    _backendCheckTimer?.cancel();
    super.dispose();
  }

  void _onNavChanged() {
    if (mounted) setState(() {});
  }

  void _tryLoadLocalSchedulesSync() {
    try {
      final local = _scheduleApiClient.loadLocalSchedules();
      if (local != null && local.classes.isNotEmpty) {
        _nav.activeClasses = local.classes;
        _nav.activeSchedules = local.schedules;
        _nav.activeSemesterStart = local.firstLessonDate;
      }
    } catch (_) {}
  }

  Future<void> _checkBackendHealth() async {
    try {
      final baseUrl = AppConfig.apiBaseUrl.replaceFirst(RegExp(r'/$'), '');
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      final online = response.statusCode == 200;
      if (mounted && _backendOnline != online) {
        setState(() => _backendOnline = online);
        if (online &&
            !_nav.resetting &&
            (_nav.activeClasses == null || _nav.activeClasses!.isEmpty)) {
          _loadInitialSavedSchedule();
        }
      }
    } catch (_) {
      if (mounted && _backendOnline != false) {
        setState(() => _backendOnline = false);
      }
    }
  }

  Future<void> _loadInitialSavedSchedule() async {
    final version = _nav.workspaceVersion;
    try {
      final saved = await _scheduleApiClient.loadSavedSchedules();
      if (saved.classes.isNotEmpty &&
          mounted &&
          !_nav.resetting &&
          version == _nav.workspaceVersion) {
        setState(() {
          _nav.activeClasses = saved.classes;
          _nav.activeSchedules = saved.schedules;
          _nav.activeSemesterStart = saved.firstLessonDate;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final compact = size.maxWidth < 1180;
      final titles = [
        'Lịch Giảng Dạy',
        'Điểm Danh QR',
        'Danh Sách Lớp',
        'Báo Cáo & Thống Kê',
      ];
      final icons = [
        Icons.calendar_month_outlined,
        Icons.qr_code_2_outlined,
        Icons.school_outlined,
        Icons.insights_outlined,
      ];
      return Scaffold(
        backgroundColor: NotionColors.surface,
        body: Row(
          children: [
            // Notion Workspace Sidebar
            Container(
              width: compact ? 68 : 240,
              decoration: const BoxDecoration(
                color: NotionColors.canvasSoft,
                border: Border(right: BorderSide(color: NotionColors.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Workspace Switcher / Identity (Sidebar Top)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: 12,
                    ),
                    child: compact
                        ? Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                'assets/app_logo.png',
                                width: 28,
                                height: 28,
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.asset(
                                    'assets/app_logo.png',
                                    width: 24,
                                    height: 24,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'iPresent Workspace',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: NotionColors.ink,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.unfold_more,
                                  size: 15,
                                  color: NotionColors.inkMuted,
                                ),
                              ],
                            ),
                          ),
                  ),

                  // Navigation list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        if (!compact)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                            child: Text(
                              'HỌC VỤ & LỊCH TRÌNH',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: NotionColors.inkMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        for (var i = 0; i < titles.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Tooltip(
                              message: compact ? titles[i] : '',
                              child: Material(
                                color: _nav.currentIndex == i
                                    ? const Color(0xFFEBEBEA)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(5),
                                  onTap: () => _nav.navigateToTab(i),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 8 : 10,
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: compact
                                          ? MainAxisAlignment.center
                                          : MainAxisAlignment.start,
                                      children: [
                                        Icon(
                                          icons[i],
                                          size: 16,
                                          color: _nav.currentIndex == i
                                              ? NotionColors.ink
                                              : NotionColors.inkMuted,
                                        ),
                                        if (!compact) ...[
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Text(
                                              titles[i],
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: _nav.currentIndex == i
                                                    ? NotionColors.ink
                                                    : NotionColors.inkSecondary,
                                                fontWeight: _nav.currentIndex == i
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const Divider(height: 1, color: NotionColors.hairline),

                  // Sidebar Footer: Quick settings
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: compact
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.end,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'Cài Đặt Dữ Liệu',
                          onSelected: (value) {
                            if (value == 'reset') _showResetDialog();
                          },
                          icon: const Icon(
                            Icons.settings_outlined,
                            size: 16,
                            color: NotionColors.inkMuted,
                          ),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'reset',
                              child: Text(
                                'Xóa Toàn Bộ Dữ Liệu',
                                style: NotionTypography.bodySm(color: const Color(0xFFB42318)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Main Content Area
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Notion Top Command Bar (Breadcrumb & Status)
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: const BoxDecoration(
                      color: NotionColors.surface,
                      border: Border(bottom: BorderSide(color: NotionColors.hairline)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.article_outlined,
                          size: 14,
                          color: NotionColors.inkMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'iPresent  /  ${titles[_nav.currentIndex.clamp(0, 3)]}',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: NotionColors.inkSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Làm mới dữ liệu',
                          onPressed: () => _checkBackendHealth(),
                          icon: const Icon(Icons.refresh, size: 15, color: NotionColors.inkMuted),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildCurrentView()),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _showResetDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppResetDialog(
        onReset: () {
          _nav.clearWorkspace();
        },
      ),
    );
  }

  Widget _buildCurrentView() {
    if (_nav.resetting) return const Center(child: Text('Đang Xóa Dữ Liệu…'));
    return IndexedStack(
      key: ValueKey(_nav.workspaceVersion),
      index: _nav.currentIndex.clamp(0, 3),
      children: [
        // Tab 0: Lịch Giảng Dạy (ScheduleGeneratorScreen)
        _nav.activeClasses != null && _nav.activeClasses!.isNotEmpty
            ? ScheduleGeneratorScreen(
                key: ValueKey(
                  'schedule-${_nav.scheduleVersion}-${_nav.activeClasses!.length}-${_nav.activeClasses!.first.offeringId}',
                ),
                importedClasses: _nav.activeClasses!,
                initialSchedules: _nav.activeSchedules,
                semesterStart: _nav.activeSemesterStart ?? DateTime.now(),
              )
            : _buildEmptySchedulePlaceholder(),

        // Tab 1: Điểm Danh QR (QrDisplayScreen)
        _nav.activeSessionId != null && _nav.activeClassId != null
            ? QrDisplayScreen(
                key: ValueKey('${_nav.activeClassId}-${_nav.activeSessionId}'),
                classId: _nav.activeClassId!,
                sessionId: _nav.activeSessionId!,
                className: _nav.activeClassName,
                lessonLabel: _nav.activeLessonLabel,
                roster: _nav.activeRoster,
                storageService: widget.storageService,
              )
            : _buildEmptyQrPlaceholder(),

        // Tab 2: Danh Sách Lớp (ImportScreen)
        const ImportScreen(),

        // Tab 3: Báo Cáo & Thống Kê (ReportsScreen)
        ReportsScreen(storageService: widget.storageService),
      ],
    );
  }

  Widget _buildEmptySchedulePlaceholder() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: NotionColors.surface,
          borderRadius: NotionRounded.lg,
          border: Border.all(color: _borderColor, width: 1),
          boxShadow: NotionElevation.soft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chưa Có Dữ Liệu Lịch Giảng Dạy',
              style: NotionTypography.heading3(color: _textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Vui lòng nạp file Markbook để hệ thống tạo thời khóa biểu và danh sách lớp học.',
              textAlign: TextAlign.center,
              style: NotionTypography.bodySm(color: _textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: NotionColors.primary,
                foregroundColor: NotionColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
              ),
              onPressed: () => _nav.navigateToTab(2),
              child: const Text(
                'Nhập File Lớp',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyQrPlaceholder() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: NotionColors.surface,
          borderRadius: NotionRounded.lg,
          border: Border.all(color: NotionColors.hairline, width: 1),
          boxShadow: NotionElevation.soft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: NotionColors.canvasSoft,
                borderRadius: NotionRounded.md,
                border: Border.all(color: NotionColors.hairline, width: 1),
              ),
              child: const Icon(
                Icons.qr_code_2_outlined,
                size: 28,
                color: NotionColors.inkMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có buổi học nào được chọn',
              style: NotionTypography.heading3(color: _textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Chọn một buổi học từ tab "Lịch Giảng Dạy" và nhấn "Tạo Phiên Điểm Danh" để mở màn hình quét mã QR.',
              textAlign: TextAlign.center,
              style: NotionTypography.bodySm(color: _textSecondary),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: NotionColors.primary,
                foregroundColor: NotionColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
              ),
              onPressed: () => _nav.navigateToTab(0),
              child: const Text(
                'Xem Lịch & Chọn Buổi Học',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
