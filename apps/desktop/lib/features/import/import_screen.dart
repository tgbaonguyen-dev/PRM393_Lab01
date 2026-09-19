import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../schedule/schedule_generator_screen.dart';
import '../schedule/services/schedule_api_client.dart';
import '../attendance/services/attendance_storage_service.dart';
import '../../shared/m1_snackbar.dart';
import '../../shell/app_shell.dart';
import 'models/import_models.dart';
import 'services/imported_class_validator.dart';
import 'services/markbook_parser.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _parser = MarkbookParser();
  final _scheduleApiClient = ScheduleApiClient();
  final _scheduleCodeController = TextEditingController();
  final _subjectCodeController = TextEditingController();
  final _classCodeController = TextEditingController();
  final _lessonCountController = TextEditingController(text: '20');
  final _studentSearchController = TextEditingController();
  final _classSearchController = TextEditingController();
  String _studentSearchQuery = '';
  String _classSearchQuery = '';

  WorkbookImportResult? _result;
  final Map<ImportedClass, ImportedClass> _editedClasses = {};
  int _selectedIndex = 0;
  ImportedClass? _hoveredClass;
  bool _isLoading = false;
  bool _isLoadingSavedSchedules = true;
  int? _savedScheduleCount;
  bool _savedScheduleCheckFailed = false;
  String? _savedScheduleCheckError;
  String? _loadError;

  ImportedClass? get _selectedClass {
    final classes = _result?.classes ?? const <ImportedClass>[];
    if (classes.isEmpty) return null;
    final original = classes[_selectedIndex];
    return _editedClasses[original] ?? original;
  }

  @override
  void dispose() {
    _scheduleCodeController.dispose();
    _subjectCodeController.dispose();
    _classCodeController.dispose();
    _lessonCountController.dispose();
    _studentSearchController.dispose();
    _classSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    await _pickAndLoad();
  }

  bool _hasAutoLoadedSavedSchedules = false;

  @override
  void initState() {
    super.initState();
    final active = AppNavigationController.instance.activeClasses;
    if (active != null && active.isNotEmpty) {
      _result = WorkbookImportResult(
        sourceFileName: 'Dữ liệu lớp hiện hành (${active.length} lớp)',
        classes: active,
      );
      _editedClasses
        ..clear()
        ..addEntries(active.map((item) => MapEntry(item, item)));
      _selectedIndex = 0;
      _loadMetadata(active.first);
    }
    _refreshSavedScheduleCount(autoOpen: false);
  }

  Future<void> _loadSavedClassesIntoView() async {
    try {
      final saved = await _scheduleApiClient.loadSavedSchedules();
      if (saved.classes.isNotEmpty && mounted) {
        setState(() {
          _result = WorkbookImportResult(
            sourceFileName: 'Dữ liệu lớp đã lưu (${saved.classes.length} lớp)',
            classes: saved.classes,
          );
          _editedClasses
            ..clear()
            ..addEntries(saved.classes.map((item) => MapEntry(item, item)));
          _selectedIndex = 0;
          _loadMetadata(saved.classes.first);
        });
        AppNavigationController.instance.activeClasses ??= saved.classes;
        AppNavigationController.instance.activeSchedules ??= saved.schedules;
        AppNavigationController.instance.activeSemesterStart ??= saved.firstLessonDate;
      }
    } catch (_) {}
  }

  Future<void> _refreshSavedScheduleCount({bool autoOpen = false}) async {
    if (mounted) {
      setState(() {
        _isLoadingSavedSchedules = true;
        _savedScheduleCheckFailed = false;
        _savedScheduleCheckError = null;
      });
    }
    try {
      final schedules = await _scheduleApiClient.listSchedules();
      if (mounted) {
        setState(() {
          _savedScheduleCount = schedules.length;
          _savedScheduleCheckFailed = false;
          _savedScheduleCheckError = null;
        });
        if (_result == null && schedules.isNotEmpty) {
          _loadSavedClassesIntoView();
        }
        if (autoOpen && !_hasAutoLoadedSavedSchedules && schedules.isNotEmpty) {
          _hasAutoLoadedSavedSchedules = true;
          _openSavedSchedules();
        }
      }
    } catch (error) {
      // A first-time installation or an offline backend simply has no saved
      // schedule entry point yet. The Markbook import remains available.
      if (mounted) {
        setState(() {
          _savedScheduleCount = null;
          _savedScheduleCheckFailed = true;
          _savedScheduleCheckError = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingSavedSchedules = false);
    }
  }

  Future<void> _openSavedSchedules() async {
    setState(() => _isLoadingSavedSchedules = true);
    try {
      final saved = await _scheduleApiClient.loadSavedSchedules();
      if (!mounted) return;
      if (saved.classes.isEmpty) {
        M1SnackBar.show(
          context,
          'Chưa có lịch nào được lưu.',
          type: M1NoticeType.warning,
        );
        return;
      }
      AppNavigationController.instance.openScheduleWithClasses(
        classes: saved.classes,
        schedules: saved.schedules,
        semesterStart: saved.firstLessonDate,
      );
      final hasShell =
          context.findAncestorStateOfType<State<AppShell>>() != null;
      if (!hasShell) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ScheduleGeneratorScreen(
              importedClasses: saved.classes,
              initialSchedules: saved.schedules,
              semesterStart: saved.firstLessonDate,
            ),
          ),
        );
      }
      if (mounted) _refreshSavedScheduleCount();
    } catch (error) {
      if (mounted) {
        M1SnackBar.show(
          context,
          'Không thể tải lịch đã lưu: $error',
          type: M1NoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSavedSchedules = false);
    }
  }

  /// A Markbook may have one class sheet or many sheets.  The same import
  /// action handles both cases; lesson counts are editable per detected class.
  Future<void> _pickAndLoad() async {
    _storeSelectedMetadata();
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'ods'],
    );
    final path = selection?.files.single.path;
    if (path == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final parsed = await _parser.parseFile(File(path));
      if (!mounted) return;
      final result = WorkbookImportResult(
        sourceFileName: parsed.sourceFileName,
        classes: validateDistinctClassOfferings(parsed.classes),
      );
      // Reset dữ liệu điểm danh cũ khi import markbook mới
      await AttendanceStorageService().resetStore();

      setState(() {
        _result = result;
        _editedClasses
          ..clear()
          ..addEntries(result.classes.map((item) => MapEntry(item, item)));
        _selectedIndex = 0;
        if (result.classes.isNotEmpty) {
          _loadMetadata(result.classes.first);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = 'Không thể đọc Markbook: $error');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectClass(int index) {
    _storeSelectedMetadata();
    setState(() {
      _selectedIndex = index;
      final original = _result!.classes[index];
      _loadMetadata(_editedClasses[original] ?? original);
    });
  }

  void _removeClass(int index) {
    final result = _result;
    if (result == null || index < 0 || index >= result.classes.length) return;

    final removed = result.classes[index];
    final remaining = List<ImportedClass>.of(result.classes)..removeAt(index);
    setState(() {
      _editedClasses.remove(removed);
      _hoveredClass = null;
      if (remaining.isEmpty) {
        _result = null;
        _selectedIndex = 0;
        _scheduleCodeController.clear();
        _subjectCodeController.clear();
        _classCodeController.clear();
        _lessonCountController.text = '20';
        return;
      }

      _result = WorkbookImportResult(
        sourceFileName: result.sourceFileName,
        classes: remaining,
      );
      _selectedIndex = index.clamp(0, remaining.length - 1);
      final next = remaining[_selectedIndex];
      _loadMetadata(_editedClasses[next] ?? next);
    });
  }

  void _loadMetadata(ImportedClass importedClass) {
    _scheduleCodeController.text = importedClass.scheduleCode;
    _subjectCodeController.text = importedClass.subjectCode;
    _classCodeController.text = importedClass.classCode;
    _lessonCountController.text = importedClass.lessonCount.toString();
  }

  void _storeSelectedMetadata() {
    final importedClass = _selectedClass;
    if (importedClass == null) return;
    final classCode = _classCodeController.text.trim().toUpperCase();
    final original = _result!.classes[_selectedIndex];
    _editedClasses[original] = importedClass.copyWith(
      scheduleCode: _scheduleCodeController.text.trim(),
      subjectCode: _subjectCodeController.text.trim().toUpperCase(),
      classCode: classCode,
      lessonCount: int.tryParse(_lessonCountController.text.trim()) ?? 0,
      students: importedClass.students
          .map((student) => student.copyWith(classCode: classCode))
          .toList(growable: false),
    );
  }

  ImportedClass _validateClassMetadata(ImportedClass importedClass) {
    const metadataIssueCodes = {
      'invalid_schedule_code',
      'missing_subject_code',
      'missing_class_code',
      'class_conflict',
      'invalid_lesson_count',
    };
    final issues = importedClass.issues
        .where((issue) => !metadataIssueCodes.contains(issue.code))
        .toList();

    void addError(String code, String message, String field) {
      issues.add(
        ImportValidationIssue(
          severity: ValidationSeverity.error,
          code: code,
          message: message,
          sheetName: importedClass.sourceSheetName,
          field: field,
        ),
      );
    }

    if (!RegExp(r'^[123][1-5]$').hasMatch(importedClass.scheduleCode)) {
      addError(
        'invalid_schedule_code',
        'Mã lịch phải theo dạng 1X, 2X hoặc 3X; X từ 1 đến 5.',
        'ScheduleCode',
      );
    }
    if (importedClass.subjectCode.trim().isEmpty) {
      addError('missing_subject_code', 'Chưa có mã môn.', 'SubjectCode');
    }
    if (importedClass.classCode.trim().isEmpty) {
      addError('missing_class_code', 'Chưa có mã lớp.', 'ClassCode');
    }

    final rosterClasses = importedClass.students
        .map((student) => student.classCode.trim().toUpperCase())
        .where((classCode) => classCode.isNotEmpty)
        .toSet();
    if (rosterClasses.length == 1 &&
        importedClass.classCode.trim().toUpperCase() != rosterClasses.single) {
      addError(
        'class_conflict',
        'Mã lớp phải khớp với cột Class (${rosterClasses.single}).',
        'ClassCode',
      );
    }
    if (importedClass.lessonCount < 1 || importedClass.lessonCount > 60) {
      addError(
        'invalid_lesson_count',
        'Số buổi phải từ 1 đến 60.',
        'LessonCount',
      );
    }
    return importedClass.copyWith(issues: issues);
  }

  void _confirmSelectedClass() {
    _storeSelectedMetadata();
    final importedClass = _selectedClass;
    if (importedClass == null) return;
    final individuallyValidated = _result!.classes
        .map((original) {
          final edited = _editedClasses[original] ?? original;
          return _validateClassMetadata(edited);
        })
        .toList(growable: false);
    final allValidated = validateDistinctClassOfferings(individuallyValidated);
    final validated = allValidated[_selectedIndex];
    setState(() {
      for (var index = 0; index < allValidated.length; index++) {
        _editedClasses[_result!.classes[index]] = allValidated[index];
      }
      _loadMetadata(validated);
    });
    final errorCount = validated.issues.where((issue) => issue.isError).length;
    M1SnackBar.show(
      context,
      errorCount == 0
          ? 'Đã xác nhận ${validated.subjectCode} - ${validated.classCode}. Có thể sinh lịch.'
          : 'Lớp này còn $errorCount lỗi. Hãy sửa các ô được báo rồi xác nhận lại.',
      type: errorCount > 0 ? M1NoticeType.error : M1NoticeType.warning,
    );
  }

  List<ImportedClass>? _prepareAllClasses() {
    _storeSelectedMetadata();
    final result = _result;
    if (result == null) return null;
    final individuallyValidated = result.classes
        .map((original) {
          final edited = _editedClasses[original] ?? original;
          return _validateClassMetadata(edited);
        })
        .toList(growable: false);
    final prepared = validateDistinctClassOfferings(individuallyValidated);
    setState(() {
      for (var index = 0; index < prepared.length; index++) {
        _editedClasses[result.classes[index]] = prepared[index];
      }
    });

    final invalidCount = prepared.where((item) {
      final metadataValid =
          RegExp(r'^[123][1-5]$').hasMatch(item.scheduleCode) &&
          item.subjectCode.trim().isNotEmpty &&
          item.classCode.trim().isNotEmpty;
      final lessonCountValid = item.lessonCount >= 1 && item.lessonCount <= 60;
      return !metadataValid ||
          !lessonCountValid ||
          item.issues.any((issue) => issue.isError);
    }).length;
    if (invalidCount > 0) {
      M1SnackBar.show(
        context,
        'Còn $invalidCount lớp chưa hợp lệ. Hãy kiểm tra mã lịch, metadata, dữ liệu và số buổi (1–60).',
        type: M1NoticeType.error,
      );
      return null;
    }
    return prepared;
  }

  Future<void> _continueToSchedule() async {
    final classes = _prepareAllClasses();
    if (classes == null || classes.isEmpty) return;
    final now = DateTime.now();
    if (!mounted) return;
    final semesterStart = await showDatePicker(
      context: context,
      helpText: 'Chọn ngày bắt đầu để sinh lịch',
      confirmText: 'Xem lịch tất cả lớp',
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3, 12, 31),
    );
    if (semesterStart == null || !mounted) return;
    final classesForSchedule = classes
        .map((item) => item.copyWith(semester: _semesterCodeFor(semesterStart)))
        .toList(growable: false);
    AppNavigationController.instance.openScheduleWithClasses(
      classes: classesForSchedule,
      semesterStart: semesterStart,
    );

    final hasShell = context.findAncestorStateOfType<State<AppShell>>() != null;
    if (!hasShell) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduleGeneratorScreen(
            importedClasses: classesForSchedule,
            initialClassIndex: _selectedIndex,
            semesterStart: semesterStart,
          ),
        ),
      );
    }
  }

  String _semesterCodeFor(DateTime start) {
    final prefix = switch (start.month) {
      <= 4 => 'SP',
      <= 8 => 'SU',
      _ => 'FA',
    };
    return '$prefix${(start.year % 100).toString().padLeft(2, '0')}';
  }

  // Notion Academic Minimalist Palette
  static const _canvasBg = Color(0xFFFAF9F6);
  static const _borderColor = Color(0xFFE3E2DE);
  static const _textPrimary = Color(0xFF37352F);
  static const _textSecondary = Color(0xFF787774);

  @override
  Widget build(BuildContext context) {
    final selectedClass = _selectedClass;
    final hasShell = context.findAncestorStateOfType<State<AppShell>>() != null;

    return Scaffold(
      backgroundColor: _canvasBg,
      appBar: hasShell
          ? null
          : AppBar(
              title: Text(
                'Nhập Markbook',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              elevation: 0,
              backgroundColor: _canvasBg,
              surfaceTintColor: Colors.transparent,
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1, thickness: 1, color: _borderColor),
              ),
            ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 14),
            if (_loadError != null) ...[
              _Banner(message: _loadError!),
              const SizedBox(height: 12),
            ],
            if (_result == null)
              Expanded(
                child: _EmptyState(
                  onPickFile: _isLoading ? null : _pickFile,
                  onLoadSaved: _isLoadingSavedSchedules ? null : _loadSavedClassesIntoView,
                  savedCount: _savedScheduleCount,
                ),
              )
            else
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 300, child: _classList()),
                    const SizedBox(width: 14),
                    if (selectedClass != null)
                      Expanded(child: _preview(selectedClass)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final result = _result;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = Row(
            mainAxisSize: MainAxisSize.min,
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
                  Icons.table_view_outlined,
                  size: 20,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bước 1 — Nhập danh sách lớp',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result == null
                          ? 'Chọn tệp .xlsx hoặc .ods. Tệp nguồn chỉ được đọc.'
                          : '${result.sourceFileName} • ${result.classes.length} lớp • ${result.totalStudents} sinh viên',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Nút Chọn Markbook
              InkWell(
                onTap: _isLoading ? null : _pickFile,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _textPrimary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading)
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.upload_file,
                          size: 15,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 7),
                      Text(
                        _isLoading ? 'Đang đọc...' : 'Chọn Markbook',
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

              // Nút Tải lại CSDL
              InkWell(
                onTap: _isLoadingSavedSchedules ? null : _loadSavedClassesIntoView,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoadingSavedSchedules)
                        const SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: _textSecondary,
                          ),
                        )
                      else
                        const Icon(
                          Icons.refresh,
                          size: 15,
                          color: _textPrimary,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        'Tải lại CSDL',
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

              // Nút Xem Lịch Giảng Dạy
              if ((_savedScheduleCount ?? 0) > 0 || (_result?.classes.isNotEmpty ?? false))
                InkWell(
                  onTap: _isLoadingSavedSchedules ? null : _openSavedSchedules,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F6F3),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _borderColor, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 15,
                          color: _textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Xem Lịch Giảng Dạy',
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

              if (_savedScheduleCheckFailed)
                Tooltip(
                  message: _savedScheduleCheckError ?? 'Backend không phản hồi tại 127.0.0.1:8080.',
                  child: InkWell(
                    onTap: _refreshSavedScheduleCount,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFCD34D), width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
                          SizedBox(width: 5),
                          Text('Offline', style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _classList() {
    final allClasses = _result!.classes;
    final query = _classSearchQuery.trim().toLowerCase();
    final classes = query.isEmpty
        ? allClasses
        : allClasses.where((item) {
            final s = _editedClasses[item] ?? item;
            return s.subjectCode.toLowerCase().contains(query) ||
                s.classCode.toLowerCase().contains(query) ||
                s.scheduleCode.toLowerCase().contains(query);
          }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Text(
                  'DANH SÁCH LỚP (${allClasses.length})',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Search box for classes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6F3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: _textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _classSearchController,
                      onChanged: (val) => setState(() => _classSearchQuery = val),
                      style: GoogleFonts.inter(fontSize: 11.5, color: _textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Lọc mã lớp, môn...',
                        hintStyle: TextStyle(fontSize: 11, color: _textSecondary),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_classSearchQuery.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _classSearchController.clear();
                        setState(() => _classSearchQuery = '');
                      },
                      child: const Icon(Icons.close, size: 12, color: _textSecondary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: _borderColor),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: classes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (_, index) {
                final item = classes[index];
                final originalIndex = allClasses.indexOf(item);
                final currentItem = _editedClasses[item] ?? item;
                final errors = currentItem.issues.where((issue) => issue.isError).length;
                final isSelected = originalIndex == _selectedIndex;
                final isHovered = identical(_hoveredClass, item);

                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredClass = item),
                  onExit: (_) {
                    if (identical(_hoveredClass, item)) {
                      setState(() => _hoveredClass = null);
                    }
                  },
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => _selectClass(originalIndex >= 0 ? originalIndex : 0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFEFEFED)
                            : (isHovered
                                ? const Color(0xFFF7F6F3)
                                : Colors.transparent),
                        borderRadius: BorderRadius.circular(5),
                        border: isSelected
                            ? Border.all(color: _borderColor, width: 1)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            errors > 0
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            size: 16,
                            color: errors > 0
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF1F7A4D),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentItem.subjectCode.isEmpty
                                      ? currentItem.sourceSheetName
                                      : currentItem.subjectCode,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${currentItem.classCode.isEmpty ? 'Chưa rõ lớp' : currentItem.classCode} • ${currentItem.students.length} SV',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F6F3),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: _borderColor, width: 0.8),
                            ),
                            child: Text(
                              'Slot ${currentItem.scheduleCode}',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: _textSecondary,
                              ),
                            ),
                          ),
                          if (isHovered) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _removeClass(originalIndex),
                              borderRadius: BorderRadius.circular(3),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Color(0xFFDC2626),
                                ),
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
        ],
      ),
    );
  }

  Widget _preview(ImportedClass importedClass) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metadataField('Mã lịch', _scheduleCodeController, 105),
                    _metadataField('Môn', _subjectCodeController, 125),
                    _metadataField('Lớp', _classCodeController, 125),
                    _metadataField('Số buổi', _lessonCountController, 110),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: _confirmSelectedClass,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 14,
                        color: _textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Xác nhận lớp',
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
              InkWell(
                onTap: _continueToSchedule,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _textPrimary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tiếp tục: Xem lịch giảng dạy',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (importedClass.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            _issues(importedClass.issues),
          ],
          const SizedBox(height: 10),
          Text(
            'Mã PRN mặc định 22 buổi, môn khác mặc định 20 buổi. Có thể điều chỉnh số buổi từ 1 đến 60 cho từng lớp.',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          // Roster Header with Search Bar
          Row(
            children: [
              Text(
                'Danh Sách Sinh Viên (${importedClass.students.length} SV)',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
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
                    const Icon(Icons.search, size: 14, color: _textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _studentSearchController,
                        onChanged: (val) => setState(() => _studentSearchQuery = val),
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
                    if (_studentSearchQuery.isNotEmpty)
                      InkWell(
                        onTap: () {
                          _studentSearchController.clear();
                          setState(() => _studentSearchQuery = '');
                        },
                        child: const Icon(Icons.close, size: 14, color: _textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Builder(
                  builder: (context) {
                    final query = _studentSearchQuery.trim().toLowerCase();
                    final filteredStudents = query.isEmpty
                        ? importedClass.students
                        : importedClass.students.where((s) {
                            return s.rollNumber.toLowerCase().contains(query) ||
                                s.fullName.toLowerCase().contains(query) ||
                                s.email.toLowerCase().contains(query) ||
                                s.memberCode.toLowerCase().contains(query);
                          }).toList();

                    if (filteredStudents.isEmpty) {
                      return Center(
                        child: Text(
                          'Không tìm thấy sinh viên nào khớp với "$_studentSearchQuery"',
                          style: GoogleFonts.inter(fontSize: 12.5, color: _textSecondary),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            const Color(0xFFF7F6F3),
                          ),
                          headingRowHeight: 36,
                          dataRowMinHeight: 34,
                          dataRowMaxHeight: 34,
                          dividerThickness: 0.8,
                          columns: [
                            DataColumn(
                              label: Text(
                                'STT',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'MSSV',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Họ và tên',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Email FPT',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Mã FAP',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Lớp',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                          rows: List.generate(filteredStudents.length, (idx) {
                            final student = filteredStudents[idx];
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    '${idx + 1}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: _textSecondary,
                                    ),
                                  ),
                                ),
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
                                DataCell(
                                  Text(
                                    student.fullName,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    student.email,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: _textSecondary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    student.memberCode,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: _textSecondary,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    student.classCode,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
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
    );
  }

  Widget _issues(List<ImportValidationIssue> issues) {
    final errorCount = issues.where((issue) => issue.isError).length;
    return Container(
      decoration: BoxDecoration(
        color: errorCount > 0
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: errorCount > 0
              ? const Color(0xFFFECACA)
              : const Color(0xFFFCD34D),
          width: 1,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          '$errorCount lỗi • ${issues.length - errorCount} cảnh báo',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: errorCount > 0
                ? const Color(0xFFB91C1C)
                : const Color(0xFFB45309),
          ),
        ),
        children: issues
            .map(
              (issue) => ListTile(
                dense: true,
                leading: Icon(
                  issue.isError ? Icons.error_outline : Icons.warning_amber,
                  size: 16,
                  color: issue.isError
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFFB45309),
                ),
                title: Text(
                  issue.message,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _textPrimary,
                  ),
                ),
                subtitle: issue.rowNumber == null
                    ? null
                    : Text(
                        'Dòng ${issue.rowNumber}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _textSecondary,
                        ),
                      ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _metadataField(
    String label,
    TextEditingController controller,
    double width,
  ) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        labelText: '$label *',
        labelStyle: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _textPrimary, width: 1.2),
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onPickFile;
  final VoidCallback? onLoadSaved;
  final int? savedCount;

  const _EmptyState({
    this.onPickFile,
    this.onLoadSaved,
    this.savedCount,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE3E2DE), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE3E2DE), width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.upload_file_outlined,
              size: 28,
              color: Color(0xFF787774),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Chưa có dữ liệu danh sách lớp',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF37352F),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Chọn tệp Markbook (.xlsx, .ods) hoặc tải từ các lớp đã lưu trong CSDL.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: const Color(0xFF787774),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF37352F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: onPickFile,
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Chọn Markbook'),
              ),
              if ((savedCount ?? 0) > 0) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF37352F),
                    side: const BorderSide(color: Color(0xFFE3E2DE)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: onLoadSaved,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Tải $savedCount lớp đã lưu'),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  final String message;
  const _Banner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFEE2E2),
      border: Border.all(color: const Color(0xFFFECACA), width: 1),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      message,
      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB91C1C)),
    ),
  );
}
