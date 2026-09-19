import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  // Notion Academic Minimalist Palette
  static const _borderColor = Color(0xFFE3E2DE);
  static const _textPrimary = Color(0xFF37352F);
  static const _textSecondary = Color(0xFF787774);

  @override
  Widget build(BuildContext context) {
    final hasMultiClasses =
        widget.availableClasses != null && widget.availableClasses!.length > 1;

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _borderColor, width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderColor, width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.file_download_outlined,
              size: 18,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Xuất Báo Cáo Điểm Danh',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.2,
            ),
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
              Text(
                'Môn học & Lớp:',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: _textPrimary,
                ),
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
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: _textPrimary),
                    ),
                    isDense: true,
                  ),
                  items: widget.availableClasses!.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        'Môn: ${c.subjectCode} | Lớp: ${c.className} (${c.roster.length} SV)',
                        style: GoogleFonts.inter(fontSize: 12.5),
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
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6F3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    'Môn: $_selectedSubjectCode  •  Lớp: $_selectedClassName  •  Học kỳ: $_selectedSemester  (${_currentRoster.length} sinh viên)',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // 2. Chọn Định dạng file xuất
              Text(
                'Định dạng file xuất:',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _formatPill(
                    label: 'Excel (.xlsx)',
                    icon: Icons.table_chart_outlined,
                    isSelected: _selectedFormat == ExportFormat.xlsx,
                    onTap: () => setState(() => _selectedFormat = ExportFormat.xlsx),
                  ),
                  const SizedBox(width: 8),
                  _formatPill(
                    label: 'CSV (.csv)',
                    icon: Icons.description_outlined,
                    isSelected: _selectedFormat == ExportFormat.csv,
                    onTap: () => setState(() => _selectedFormat = ExportFormat.csv),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3. Chọn Chế độ Slot (3 trường hợp)
              Text(
                'Chọn Buổi học (Slots) cần xuất:',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _slotModePill(
                    label: '1 Slot',
                    icon: Icons.today_outlined,
                    isSelected: _slotMode == ExportSlotMode.singleSlot,
                    onTap: () => setState(() => _slotMode = ExportSlotMode.singleSlot),
                  ),
                  const SizedBox(width: 8),
                  _slotModePill(
                    label: 'Nhiều Slot',
                    icon: Icons.checklist_rounded,
                    isSelected: _slotMode == ExportSlotMode.multiSlots,
                    onTap: () => setState(() => _slotMode = ExportSlotMode.multiSlots),
                  ),
                  const SizedBox(width: 8),
                  _slotModePill(
                    label: 'Cả 20 Slot',
                    icon: Icons.calendar_month_outlined,
                    isSelected: _slotMode == ExportSlotMode.all20Slots,
                    onTap: () => setState(() => _slotMode = ExportSlotMode.all20Slots),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Chi tiết theo từng chế độ Slot
              if (_slotMode == ExportSlotMode.singleSlot) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6F3),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Chọn slot duy nhất:',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _singleSelectedSlot,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: _borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: const BorderSide(color: _textPrimary),
                            ),
                            isDense: true,
                          ),
                          items: List.generate(20, (i) => i + 1).map((slot) {
                            final date = _currentLessonDates[slot];
                            final dateText = date != null ? ' ($date)' : '';
                            return DropdownMenuItem(
                              value: slot,
                              child: Text(
                                'Slot ${slot.toString().padLeft(2, '0')}$dateText',
                                style: GoogleFonts.inter(fontSize: 12),
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6F3),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Đã chọn ${_multiSelectedSlots.length}/20 slot',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
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
                                child: Text(
                                  'Chọn hết',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Text(
                                ' • ',
                                style: TextStyle(color: _borderColor),
                              ),
                              InkWell(
                                onTap: () =>
                                    setState(() => _multiSelectedSlots.clear()),
                                child: Text(
                                  'Bỏ chọn',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: _textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: List.generate(20, (i) {
                          final slot = i + 1;
                          final isSelected = _multiSelectedSlots.contains(slot);
                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _multiSelectedSlots.remove(slot);
                                } else {
                                  _multiSelectedSlots.add(slot);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(3),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _textPrimary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: isSelected
                                      ? _textPrimary
                                      : _borderColor,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                slot.toString().padLeft(2, '0'),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? Colors.white
                                      : _textPrimary,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF5F0),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFC6E7D6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF1F7A4D),
                        size: 15,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Sẽ xuất toàn bộ 20 cột điểm danh (Slot 01 đến Slot 20).',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFF1F7A4D),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFB91C1C),
                      fontSize: 12,
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
          child: Text(
            'Hủy',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: _textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        InkWell(
          onTap: _isExporting ? null : _handleExport,
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
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.save_alt_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                const SizedBox(width: 6),
                Text(
                  _isExporting ? 'Đang xuất...' : 'Lưu File',
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
    );
  }

  Widget _formatPill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? _textPrimary : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? _textPrimary : _borderColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : _textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : _textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slotModePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? _textPrimary : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? _textPrimary : _borderColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : _textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? Colors.white : _textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
