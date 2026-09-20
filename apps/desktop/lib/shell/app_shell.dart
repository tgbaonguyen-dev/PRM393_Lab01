import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../features/import/import_screen.dart';
import '../features/import/models/import_models.dart';
import '../features/reports/reports_screen.dart';
import '../features/schedule/models/schedule_models.dart';
import '../features/schedule/schedule_generator_screen.dart';
import '../features/schedule/services/schedule_api_client.dart';
import '../features/session/qr_display_screen.dart';

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
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppNavigationController _nav = AppNavigationController.instance;
  final ScheduleApiClient _scheduleApiClient = ScheduleApiClient();
  final TextEditingController _searchController = TextEditingController();

  bool _backendOnline = false;
  Timer? _backendCheckTimer;

  // Bảng màu Notion Workspace / Academic Minimalist
  static const _canvasBg = Color(0xFFFAF9F6); // Base Canvas
  static const _sidebarBg = Color(0xFFF7F6F3); // Sidebar Surface
  static const _borderColor = Color(0xFFE3E2DE); // Border / Divider 1px
  static const _textPrimary = Color(0xFF37352F); // Than chì tự nhiên
  static const _textSecondary = Color(0xFF787774); // Xám ấm
  static const _textTertiary = Color(0xFF9B9A97); // Gợi ý / Breadcrumb
  static const _activeItemBg = Color(0xFFEFEFED); // Active row

  @override
  void initState() {
    super.initState();
    _nav.addListener(_onNavChanged);
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
    _searchController.dispose();
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
      final response = await http
          .get(Uri.parse('http://127.0.0.1:8080/health'))
          .timeout(const Duration(seconds: 2));
      final online = response.statusCode == 200;
      if (mounted && _backendOnline != online) {
        setState(() => _backendOnline = online);
        if (online && (_nav.activeClasses == null || _nav.activeClasses!.isEmpty)) {
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
    try {
      final saved = await _scheduleApiClient.loadSavedSchedules();
      if (saved.classes.isNotEmpty && mounted) {
        setState(() {
          _nav.activeClasses = saved.classes;
          _nav.activeSchedules = saved.schedules;
          _nav.activeSemesterStart = saved.firstLessonDate;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvasBg,
      body: Row(
        children: [
          // 1. Notion Sidebar (240px)
          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: _sidebarBg,
              border: Border(right: BorderSide(color: _borderColor, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Brand Card (iPresent)
                _buildSidebarProfile(),
                const Divider(height: 1, color: _borderColor),

                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    children: [
                      _buildSectionHeader('HỌC VỤ'),
                      const SizedBox(height: 4),
                      _buildSidebarItem(
                        index: 0,
                        title: 'Lịch Giảng Dạy',
                        icon: Icons.calendar_today_outlined,
                        onTap: () => _nav.navigateToTab(0),
                      ),
                      _buildSidebarItem(
                        index: 1,
                        title: 'Điểm Danh QR',
                        icon: Icons.qr_code_scanner_outlined,
                        onTap: () => _nav.navigateToTab(1),
                      ),
                      _buildSidebarItem(
                        index: 2,
                        title: 'Danh Sách Lớp',
                        icon: Icons.school_outlined,
                        onTap: () => _nav.navigateToTab(2),
                      ),
                      _buildSidebarItem(
                        index: 3,
                        title: 'Báo Cáo & Thống Kê',
                        icon: Icons.bar_chart_outlined,
                        onTap: () => _nav.navigateToTab(3),
                      ),
                    ],
                  ),
                ),

                // Sidebar Footer (Minimal & Crisp)
                const Divider(height: 1, color: _borderColor),
                _buildSidebarFooter(),
              ],
            ),
          ),

          // 2. Main Content View with Top Bar
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopAppBar(),
                Expanded(
                  child: _buildCurrentView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarProfile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF37352F),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              'iP',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'iPresent',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1F7A4D),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Workspace',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFFEFEFED),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _borderColor, width: 0.8),
            ),
            child: Text(
              'v3.4',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: _textTertiary,
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required String title,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    final isSelected = _nav.currentIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          hoverColor: const Color(0xFFEAE9E5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected ? _activeItemBg : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: isSelected ? _textPrimary : _textSecondary,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: _textPrimary,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: const BoxDecoration(
                      color: _textPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _backendOnline
                  ? const Color(0xFF1F7A4D)
                  : const Color(0xFFB87214),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _backendOnline ? 'Cloud Synced' : 'Offline Mode',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _textSecondary,
              ),
            ),
          ),
          Text(
            'v3.4',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              color: _textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar() {
    final titles = [
      'Lịch Giảng Dạy Tuần',
      'Điểm Danh QR Trực Tiếp',
      'Nhập Danh Sách Lớp & Markbook',
      'Báo Cáo & Thống Kê Điểm Danh',
    ];
    final currentTitle = titles[_nav.currentIndex.clamp(0, titles.length - 1)];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _canvasBg,
        border: Border(bottom: BorderSide(color: _borderColor, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 640;
          final showSearch = constraints.maxWidth > 780;

          return Row(
            children: [
              // Breadcrumb
              if (!isCompact) ...[
                Text(
                  'Học Kỳ 2 (2024–2025)',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: _textTertiary,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('/', style: TextStyle(color: _borderColor, fontSize: 13)),
                ),
              ],
              Flexible(
                child: Text(
                  currentTitle,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ),
              const Spacer(),

              // Search Bar (⌘K)
              if (showSearch) ...[
                Container(
                  width: 220,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 14, color: _textTertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => _nav.updateSearch(val),
                          style: const TextStyle(fontSize: 12, color: _textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Tìm Kiếm... (⌘K)',
                            hintStyle: TextStyle(fontSize: 11.5, color: _textTertiary),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],

              // Status Chip: Đã Đồng Bộ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _backendOnline ? const Color(0xFFEBF5F0) : const Color(0xFFFDF5E6),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _backendOnline ? const Color(0xFFC6E7D6) : const Color(0xFFF6DEB8),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _backendOnline ? const Color(0xFF1F7A4D) : const Color(0xFFB87214),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _backendOnline ? 'Đã Đồng Bộ' : 'Ngoại Tuyến',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _backendOnline ? const Color(0xFF1F7A4D) : const Color(0xFFB87214),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCurrentView() {
    return IndexedStack(
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
              )
            : _buildEmptyQrPlaceholder(),

        // Tab 2: Danh Sách Lớp (ImportScreen)
        const ImportScreen(),

        // Tab 3: Báo Cáo & Thống Kê (ReportsScreen)
        const ReportsScreen(),
      ],
    );
  }

  Widget _buildEmptySchedulePlaceholder() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Chưa Có Dữ Liệu Lịch Giảng Dạy',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vui lòng nạp file Markbook để hệ thống tạo thời khóa biểu và danh sách lớp học.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: _textPrimary,
                foregroundColor: Colors.white,
                side: const BorderSide(color: _textPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => _nav.navigateToTab(2),
              child: const Text('Nhập File Lớp', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyQrPlaceholder() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderColor, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sẵn Sàng Phát Mã QR',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn một buổi học từ tab "Lịch Giảng Dạy" và nhấn "Tạo Phiên Điểm Danh" để mở màn hình quét mã QR.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: _textPrimary,
                foregroundColor: Colors.white,
                side: const BorderSide(color: _textPrimary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => _nav.navigateToTab(0),
              child: const Text('Xem Lịch & Chọn Buổi Học', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
