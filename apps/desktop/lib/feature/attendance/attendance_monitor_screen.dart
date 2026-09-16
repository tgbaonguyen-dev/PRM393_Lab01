import 'dart:async';
import 'package:flutter/material.dart';
import 'models/attendance_model.dart';
import 'attendance_api_service.dart';
import 'widgets/attendance_summary_card.dart';
import 'widgets/student_attendance_table.dart';
import '../../features/export/export_dialog.dart';
import '../../features/attendance/services/attendance_storage_service.dart';

/// Màn hình Giám sát Điểm danh Realtime & Sửa kết quả thủ công (Thành viên 4)
/// Phụ trách: DES-03, DES-04, DES-05, API-08, FR-11, FR-14, AC-10
class AttendanceMonitorScreen extends StatefulWidget {
  final String sessionId;
  final String className;
  final String subjectCode;
  final int lessonSequence;

  const AttendanceMonitorScreen({
    super.key,
    required this.sessionId,
    this.className = 'SE1917',
    this.subjectCode = 'PRM393',
    this.lessonSequence = 1,
  });

  @override
  State<AttendanceMonitorScreen> createState() =>
      _AttendanceMonitorScreenState();
}

class _AttendanceMonitorScreenState extends State<AttendanceMonitorScreen> {
  final AttendanceApiService _apiService = AttendanceApiService();

  Timer? _pollingTimer;
  List<StudentAttendanceRecord> _students = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _errorMessage;
  DateTime? _lastSyncTime;

  @override
  void initState() {
    super.initState();
    // 1. Tải dữ liệu ban đầu
    _fetchAttendanceData();

    // 2. Kích hoạt Live Polling mỗi 5 giây (FR-11, DES-03)
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchAttendanceData(isBackground: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Gọi API lấy dữ liệu điểm danh
  Future<void> _fetchAttendanceData({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final result = await _apiService.getAttendances(widget.sessionId);
      if (mounted) {
        setState(() {
          _students = result.students;
          _isLoading = false;
          _errorMessage = null;
          _lastSyncTime = DateTime.now();
        });

        // Tự động lưu vào bộ nhớ cục bộ để khi xuất file luôn có P/A
        _persistCurrentSlotAttendance();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!isBackground) {
            _errorMessage = e.toString();
          }
        });
      }
    }
  }

  /// Xử lý Giảng viên sửa A <-> P thủ công (FR-14, AC-10)
  Future<void> _handleManualOverride(
    StudentAttendanceRecord student,
    String newStatus,
  ) async {
    setState(() => _isUpdating = true);

    try {
      final success = await _apiService.updateManualStatus(
        sessionId: widget.sessionId,
        studentEmail: student.email,
        newStatus: newStatus,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã cập nhật ${student.fullName} sang trạng thái "$newStatus"',
              ),
              backgroundColor: newStatus == 'P'
                  ? const Color(0xFF059669)
                  : const Color(0xFFDC2626),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        // Làm mới lại dữ liệu ngay lập tức
        await _fetchAttendanceData(isBackground: true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể cập nhật kết quả điểm danh. Vui lòng thử lại.',
              ),
              backgroundColor: Color(0xFFDC2626),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  /// Lưu điểm danh slot hiện tại vào file JSON cục bộ
  Future<void> _persistCurrentSlotAttendance() async {
    try {
      final storage = AttendanceStorageService();
      final store = await storage.loadStore();
      final classKey = widget.className;
      final classStore = store.putIfAbsent(classKey, () => {});

      final currentSlotMap = <String, String>{};
      for (final s in _students) {
        if (s.status.isNotEmpty) {
          currentSlotMap[s.email.toLowerCase()] = s.status;
        }
      }
      classStore[widget.lessonSequence] = currentSlotMap;
      await storage.saveStore(store);
    } catch (_) {}
  }

  /// Mở hộp thoại xuất báo cáo điểm danh Excel (.xlsx) / CSV (.csv)
  Future<void> _openExportDialog() async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có dữ liệu sinh viên để xuất báo cáo.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final roster = _students
        .map(
          (s) => {
            'rollNumber': s.rollNumber,
            'fullName': s.fullName,
            'email': s.email,
            'memberCode': s.rollNumber,
          },
        )
        .toList();

    // Nạp toàn bộ các slot đã lưu từ trước
    final storage = AttendanceStorageService();
    final store = await storage.loadStore();
    final classStore = store[widget.className] ?? <int, Map<String, String>>{};

    final attendanceData = <String, Map<int, String>>{};
    for (final s in _students) {
      final emailKey = s.email.toLowerCase();
      final slotMap = <int, String>{};

      // Nạp từ lịch sử các slot
      classStore.forEach((slotNum, studentMap) {
        final status = studentMap[emailKey] ?? '';
        if (status.isNotEmpty) {
          slotMap[slotNum] = status;
        }
      });

      // Ghi đè trạng thái slot hiện tại đang mở
      if (s.status.isNotEmpty) {
        slotMap[widget.lessonSequence] = s.status;
      }

      attendanceData[emailKey] = slotMap;
    }

    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final lessonDates = <int, String>{widget.lessonSequence: dateStr};

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => ExportDialog(
        subjectCode: widget.subjectCode,
        className: widget.className,
        semester: 'FA26',
        roster: roster,
        lessonDates: lessonDates,
        attendanceData: attendanceData,
        currentLessonSequence: widget.lessonSequence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${widget.subjectCode} - ${widget.className}',
                style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Buổi học số ${widget.lessonSequence}',
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          // Nút Xuất Báo Cáo Excel / CSV (M5)
          IconButton(
            tooltip: 'Xuất báo cáo Excel / CSV',
            icon: const Icon(
              Icons.file_download_outlined,
              color: Color(0xFF2563EB),
            ),
            onPressed: _openExportDialog,
          ),
          const SizedBox(width: 4),

          // Indicator trạng thái Live Polling 5s
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _lastSyncTime != null
                      ? 'Live: ${_lastSyncTime!.hour.toString().padLeft(2, '0')}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}:${_lastSyncTime!.second.toString().padLeft(2, '0')}'
                      : 'Đang kết nối...',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Làm mới thủ công',
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF475569),
                  ),
                  onPressed: () => _fetchAttendanceData(),
                ),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Không thể tải dữ liệu: $_errorMessage',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _fetchAttendanceData(),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Thẻ thống kê Sĩ số Realtime (Live Counters)
                  AttendanceSummaryCards(
                    attendanceList: _students,
                    isLive: true,
                  ),
                  const SizedBox(height: 24),

                  // 2. Bảng Danh sách Sinh viên & Nút Sửa tay
                  Expanded(
                    child: StudentAttendanceTable(
                      students: _students,
                      isUpdating: _isUpdating,
                      onStatusChanged: (student, newStatus) {
                        _handleManualOverride(student, newStatus);
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
