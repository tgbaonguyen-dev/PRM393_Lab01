import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'export_report_service.dart';

enum ExportFormat { xlsx, csv }

enum ExportSlotMode {
  singleSlot, // 1. Chọn đúng 1 slot duy nhất
  multiSlots, // 2. Chọn nhiều slot tùy ý (ví dụ: 1, 2, 5, 9)
  all20Slots, // 3. Xuất toàn bộ 20 slot
}

/// Dữ liệu lớp học phục vụ xuất báo cáo
class ExportClassOption {
  final String subjectCode;
  final String className;
  final String semester;
  final List<Map<String, dynamic>> roster;
  final Map<int, String> lessonDates;
  final Map<String, Map<int, String>> attendanceData;

  const ExportClassOption({
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
      _selectedSubjectCode = opt.subjectCode;
      _selectedClassName = opt.className;
      _selectedSemester = opt.semester;
      _currentRoster = opt.roster;
      _currentLessonDates = opt.lessonDates;
      _currentAttendanceData = opt.attendanceData;
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
                : 'All20Slots');

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
    final hasMultiClasses =
        widget.availableClasses != null && widget.availableClasses!.length > 1;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.file_download_outlined,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Xuất Báo Cáo Điểm Danh',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Chọn Môn học & Lớp học
              const Text(
                'Môn học & Lớp:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (hasMultiClasses) ...[
                DropdownButtonFormField<ExportClassOption>(
                  initialValue: widget.availableClasses!.firstWhere(
                    (c) =>
                        c.subjectCode == _selectedSubjectCode &&
                        c.className == _selectedClassName,
                    orElse: () => widget.availableClasses!.first,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: widget.availableClasses!.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        'Môn: ${c.subjectCode} | Lớp: ${c.className} (${c.roster.length} SV)',
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: _onClassChanged,
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'Môn: $_selectedSubjectCode  •  Lớp: $_selectedClassName  •  Học kỳ: $_selectedSemester  (${_currentRoster.length} sinh viên)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 2. Chọn Định dạng file xuất
              const Text(
                'Định dạng file xuất:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ExportFormat>(
                  segments: const [
                    ButtonSegment(
                      value: ExportFormat.xlsx,
                      label: Text('Excel (.xlsx)'),
                      icon: Icon(Icons.table_chart_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: ExportFormat.csv,
                      label: Text('CSV (.csv)'),
                      icon: Icon(Icons.description_outlined, size: 18),
                    ),
                  ],
                  selected: {_selectedFormat},
                  onSelectionChanged: (set) =>
                      setState(() => _selectedFormat = set.first),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Chọn Chế độ Slot (3 trường hợp)
              const Text(
                'Chọn Buổi học (Slots) cần xuất:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ExportSlotMode>(
                  segments: const [
                    ButtonSegment(
                      value: ExportSlotMode.singleSlot,
                      label: Text('1 Slot'),
                      icon: Icon(Icons.today_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: ExportSlotMode.multiSlots,
                      label: Text('Nhiều Slot'),
                      icon: Icon(Icons.checklist_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: ExportSlotMode.all20Slots,
                      label: Text('Cả 20 Slot'),
                      icon: Icon(Icons.calendar_month_outlined, size: 16),
                    ),
                  ],
                  selected: {_slotMode},
                  onSelectionChanged: (set) =>
                      setState(() => _slotMode = set.first),
                ),
              ),
              const SizedBox(height: 12),

              // Chi tiết theo từng chế độ Slot
              if (_slotMode == ExportSlotMode.singleSlot) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Chọn slot duy nhất:',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _singleSelectedSlot,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: List.generate(20, (i) => i + 1).map((slot) {
                            final date = _currentLessonDates[slot];
                            final dateText = date != null ? ' ($date)' : '';
                            return DropdownMenuItem(
                              value: slot,
                              child: Text(
                                'Slot ${slot.toString().padLeft(2, '0')}$dateText',
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _singleSelectedSlot = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_slotMode == ExportSlotMode.multiSlots) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Đã chọn ${_multiSelectedSlots.length}/20 slot',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _multiSelectedSlots.addAll(
                                      List.generate(20, (i) => i + 1),
                                    );
                                  });
                                },
                                child: const Text(
                                  'Chọn hết',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF2563EB),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Text(
                                ' • ',
                                style: TextStyle(color: Color(0xFF94A3B8)),
                              ),
                              InkWell(
                                onTap: () =>
                                    setState(() => _multiSelectedSlots.clear()),
                                child: const Text(
                                  'Bỏ chọn',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(20, (i) {
                          final slot = i + 1;
                          final isSelected = _multiSelectedSlots.contains(slot);
                          return FilterChip(
                            label: Text(
                              slot.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            showCheckmark: false,
                            selectedColor: const Color(0xFFDBEAFE),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _multiSelectedSlots.add(slot);
                                } else {
                                  _multiSelectedSlots.remove(slot);
                                }
                              });
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF16A34A),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sẽ xuất toàn bộ 20 cột điểm danh (Slot 01 đến Slot 20).',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          onPressed: _isExporting ? null : _handleExport,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          icon: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_alt_rounded, size: 18),
          label: Text(_isExporting ? 'Đang xuất...' : 'Lưu File'),
        ),
      ],
    );
  }
}
