import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../shared/notion_tokens.dart';
import 'export_report_service.dart';
import '../attendance/services/attendance_storage_service.dart';

enum ExportFormat { xlsx, csv }

enum ExportSlotMode {
  singleSlot, // 1. Chọn đúng 1 slot duy nhất
  multiSlots, // 2. Chọn nhiều slot tùy ý (ví dụ: 1, 2, 5, 9)
  all20Slots, // 3. Xuất toàn bộ 20 slot
}

/// Dữ liệu lớp học phục vụ xuất báo cáo
class ExportClassOption {
  final String? scheduleCode;
  final String subjectCode;
  final String className;
  final String semester;
  final List<Map<String, dynamic>> roster;
  final Map<int, String> lessonDates;
  final Map<String, Map<int, String>> attendanceData;

  const ExportClassOption({
    this.scheduleCode,
    required this.subjectCode,
    required this.className,
    this.semester = 'FA26',
    required this.roster,
    this.lessonDates = const {},
    this.attendanceData = const {},
  });

  String get displayName => '$subjectCode - $className';
}

class ExportDialog extends StatefulWidget {
  final String? scheduleCode;
  final String subjectCode;
  final String className;
  final String semester;
  final List<Map<String, dynamic>> roster;
  final Map<int, String> lessonDates;
  final Map<String, Map<int, String>> attendanceData;
  final int? currentLessonSequence;
  final List<ExportClassOption>? availableClasses;

  const ExportDialog({
    super.key,
    this.scheduleCode,
    required this.subjectCode,
    required this.className,
    this.semester = 'FA26',
    required this.roster,
    required this.lessonDates,
    required this.attendanceData,
    this.currentLessonSequence,
    this.availableClasses,
  });

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  final ExportReportService _exportService = ExportReportService();

  // 1. Quản lý Môn & Lớp học
  String? _selectedScheduleCode;
  late String _selectedSubjectCode;
  late String _selectedClassName;
  late String _selectedSemester;
  late List<Map<String, dynamic>> _currentRoster;
  late Map<int, String> _currentLessonDates;
  late Map<String, Map<int, String>> _currentAttendanceData;

  // 2. Định dạng xuất
  ExportFormat _selectedFormat = ExportFormat.xlsx;

  // 3. Chế độ chọn Slot (3 trường hợp)
  ExportSlotMode _slotMode = ExportSlotMode.all20Slots;
  late int _singleSelectedSlot;
  final Set<int> _multiSelectedSlots = <int>{};

  bool _isExporting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedScheduleCode = widget.scheduleCode;
    _selectedSubjectCode = widget.subjectCode;
    _selectedClassName = widget.className;
    _selectedSemester = widget.semester;
    _currentRoster = widget.roster;
    _currentLessonDates = widget.lessonDates;
    _currentAttendanceData = widget.attendanceData;

    _singleSelectedSlot = widget.currentLessonSequence ?? 1;

    if (widget.currentLessonSequence != null) {
      _multiSelectedSlots.add(widget.currentLessonSequence!);
      _slotMode = ExportSlotMode.singleSlot;
    } else {
      _multiSelectedSlots.addAll([1, 2, 3]);
      _slotMode = ExportSlotMode.all20Slots;
    }
  }

  void _onClassChanged(ExportClassOption? opt) {
    if (opt == null) return;
    setState(() {
      _selectedScheduleCode = opt.scheduleCode;
      _selectedSubjectCode = opt.subjectCode;
      _selectedClassName = opt.className;
      _selectedSemester = opt.semester;
      _currentRoster = opt.roster;
      _currentLessonDates = opt.lessonDates;
      _currentAttendanceData = opt.attendanceData;
      final valid = _currentLessonDates.keys.toSet();
      if (valid.isNotEmpty) {
        if (!valid.contains(_singleSelectedSlot)) {
          _singleSelectedSlot = valid.reduce((a, b) => a < b ? a : b);
        }
        _multiSelectedSlots.removeWhere((n) => !valid.contains(n));
      }
    });
  }

  List<int> get _targetLessons {
    switch (_slotMode) {
      case ExportSlotMode.singleSlot:
        return [_singleSelectedSlot];
      case ExportSlotMode.multiSlots:
        final list = _multiSelectedSlots.toList()..sort();
        return list.isNotEmpty ? list : [_singleSelectedSlot];
      case ExportSlotMode.all20Slots:
        if (_currentLessonDates.isNotEmpty) {
          return _currentLessonDates.keys.toList()..sort();
        }
        return List.generate(20, (i) => i + 1);
    }
  }

  Future<void> _handleExport() async {
    if (_slotMode == ExportSlotMode.multiSlots && _multiSelectedSlots.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng chọn ít nhất một buổi học (Slot).';
      });
      return;
    }

    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      final ext = _selectedFormat == ExportFormat.xlsx ? 'xlsx' : 'csv';
      final slotsLabel = _slotMode == ExportSlotMode.singleSlot
          ? 'Slot${_singleSelectedSlot.toString().padLeft(2, '0')}'
          : (_slotMode == ExportSlotMode.multiSlots
                ? 'MultiSlots'
                : 'All${_targetLessons.length}Slots');

      final defaultFileName =
          '${_selectedSubjectCode}_${_selectedClassName}_${_selectedSemester}_$slotsLabel.$ext';

      // 1. Mở FilePicker lưu file
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

      final finalPath = savePath.endsWith('.$ext')
          ? savePath
          : '$savePath.$ext';

      final store = await AttendanceStorageService().fetchLatestStore();
      if (!mounted) return;
      final latest = AttendanceStorageService.resolveClassAttendance(
        store: store,
        scheduleCode: _selectedScheduleCode,
        subjectCode: _selectedSubjectCode,
        classCode: _selectedClassName,
      );
      _currentAttendanceData = {
        for (final student in _currentRoster)
          (student['email'] ?? '').toString().trim().toLowerCase(): {
            for (final slot in latest.entries)
              if (slot.value.containsKey(
                (student['email'] ?? '').toString().trim().toLowerCase(),
              ))
                slot.key:
                    slot.value[(student['email'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase()]!,
          },
      };

      // 2. Gọi Service xuất file
      late final ExportResult result;
      if (_selectedFormat == ExportFormat.xlsx) {
        result = await _exportService.exportToExcel(
          subjectCode: _selectedSubjectCode,
          className: _selectedClassName,
          semester: _selectedSemester,
          roster: _currentRoster,
          selectedLessonNumbers: _targetLessons,
          lessonDates: _currentLessonDates,
          attendanceData: _currentAttendanceData,
          targetFilePath: finalPath,
        );
      } else {
        result = await _exportService.exportToCsv(
          subjectCode: _selectedSubjectCode,
          className: _selectedClassName,
          roster: _currentRoster,
          selectedLessonNumbers: _targetLessons,
          lessonDates: _currentLessonDates,
          attendanceData: _currentAttendanceData,
          targetFilePath: finalPath,
        );
      }

      if (!mounted) return;

      if (result.success) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đã xuất thành công (${result.studentCount} SV, ${result.lessonCount} Slots):\n${File(finalPath).path}',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Xuất file thất bại.';
          _isExporting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isExporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _currentLessonDates.isEmpty
        ? List.generate(20, (i) => i + 1)
        : (_currentLessonDates.keys.toList()..sort());
    return PopScope(
      canPop: !_isExporting,
      child: AlertDialog(
        backgroundColor: NotionColors.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: NotionRounded.lg,
          side: const BorderSide(color: NotionColors.hairline),
        ),
        title: Text(
          'Xuất Báo Cáo Điểm Danh',
          style: NotionTypography.heading3(color: NotionColors.ink),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: AbsorbPointer(
              absorbing: _isExporting,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Điểm danh mới nhất sẽ được lấy tự động trước khi lưu file.',
                    style: NotionTypography.caption(color: NotionColors.inkMuted),
                  ),
                  const SizedBox(height: 20),
                  if (widget.availableClasses != null &&
                      widget.availableClasses!.isNotEmpty)
                    DropdownButtonFormField<ExportClassOption>(
                      initialValue: widget.availableClasses!.firstWhere(
                        (c) =>
                            c.subjectCode == _selectedSubjectCode &&
                            c.className == _selectedClassName,
                        orElse: () => widget.availableClasses!.first,
                      ),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Lớp Học Phần',
                      ),
                      items: widget.availableClasses!
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _onClassChanged,
                    )
                  else
                    Text(
                      '$_selectedSubjectCode · $_selectedClassName · $_selectedSemester',
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final format in ExportFormat.values)
                        ChoiceChip(
                          label: Text(
                            format == ExportFormat.xlsx
                                ? 'Excel (.xlsx)'
                                : 'CSV (.csv)',
                          ),
                          selected: _selectedFormat == format,
                          onSelected: (_) =>
                              setState(() => _selectedFormat = format),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ExportSlotMode>(
                    initialValue: _slotMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Phạm Vi Xuất',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ExportSlotMode.all20Slots,
                        child: Text('Tất Cả Buổi Học'),
                      ),
                      DropdownMenuItem(
                        value: ExportSlotMode.singleSlot,
                        child: Text('Một Buổi Học'),
                      ),
                      DropdownMenuItem(
                        value: ExportSlotMode.multiSlots,
                        child: Text('Chọn Nhiều Buổi'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) setState(() => _slotMode = mode);
                    },
                  ),
                  if (_slotMode != ExportSlotMode.all20Slots) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: lessons
                          .map(
                            (n) => FilterChip(
                              label: Text(
                                'Buổi $n',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: (_slotMode == ExportSlotMode.singleSlot
                                          ? n == _singleSelectedSlot
                                          : _multiSelectedSlots.contains(n))
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              selected: _slotMode == ExportSlotMode.singleSlot
                                  ? n == _singleSelectedSlot
                                  : _multiSelectedSlots.contains(n),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              showCheckmark: false,
                              selectedColor: NotionColors.canvasSoft,
                              backgroundColor: NotionColors.surface,
                              side: BorderSide(
                                color: (_slotMode == ExportSlotMode.singleSlot
                                        ? n == _singleSelectedSlot
                                        : _multiSelectedSlots.contains(n))
                                    ? NotionColors.ink
                                    : NotionColors.hairline,
                              ),
                              onSelected: (v) => setState(() {
                                if (_slotMode == ExportSlotMode.singleSlot) {
                                  _singleSelectedSlot = n;
                                } else if (v) {
                                  _multiSelectedSlots.add(n);
                                } else {
                                  _multiSelectedSlots.remove(n);
                                }
                              }),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '${_currentRoster.length} sinh viên · ${_targetLessons.length} buổi học',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF787774),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB42318),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isExporting ? null : () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: _isExporting ? null : _handleExport,
            child: Text(_isExporting ? 'Đang Cập Nhật Và Xuất…' : 'Lưu File'),
          ),
        ],
      ),
    );
  }
}
