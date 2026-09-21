import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../schedule/models/schedule_models.dart';
import '../schedule/schedule_generator_screen.dart';
import '../schedule/services/schedule_api_client.dart';
import '../schedule/services/schedule_generator.dart';
import '../schedule/services/schedule_overview.dart';
import '../attendance/services/attendance_storage_service.dart';
import '../../shared/m1_snackbar.dart';
import '../../shared/notion_tokens.dart';
import '../../shared/workspace_ui.dart';
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
  final _rosterHorizontalScrollController = ScrollController();
  final _rosterVerticalScrollController = ScrollController();
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
    _rosterHorizontalScrollController.dispose();
    _rosterVerticalScrollController.dispose();
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
        AppNavigationController.instance.activeSemesterStart ??=
            saved.firstLessonDate;
      }
    } catch (_) {}
  }

  Future<void> _refreshSavedScheduleCount({bool autoOpen = false}) async {
    if (mounted) {
      setState(() {
        _isLoadingSavedSchedules = true;
        _savedScheduleCheckFailed = false;
      });
    }
    try {
      final schedules = await _scheduleApiClient.listSchedules();
      if (mounted) {
        setState(() {
          _savedScheduleCount = schedules.length;
          _savedScheduleCheckFailed = false;
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

      // Cho phép giảng viên chọn ngày bắt đầu học kỳ trước khi sinh lịch
      final preparedClasses = _prepareAllClasses();
      if (preparedClasses != null && preparedClasses.isNotEmpty) {
        if (!mounted) return;
        final now = DateTime.now();
        final pickedDate = await showDatePicker(
          context: context,
          helpText: 'Chọn ngày bắt đầu học kỳ để sinh lịch giảng dạy',
          confirmText: 'Xác Nhận Ngày',
          initialDate: DateTime(now.year, now.month, now.day),
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 3, 12, 31),
        );
        if (!mounted) return;

        final semesterStart = pickedDate != null
            ? ScheduleOverview.startOfWeek(pickedDate)
            : (AppNavigationController.instance.activeSemesterStart ??
                ScheduleOverview.startOfWeek(DateTime(now.year, now.month, now.day)));
        final semesterCode = _semesterCodeFor(semesterStart);
        final classesForSchedule = preparedClasses
            .map((item) => item.copyWith(semester: semesterCode))
            .toList(growable: false);

        final schedules = <String, List<ClassLesson>>{};
        for (final item in classesForSchedule) {
          final firstDate = ScheduleGenerator.firstTeachingDateOnOrAfter(
            scheduleCode: item.scheduleCode,
            semesterStart: semesterStart,
          );
          schedules[item.sourceSheetName] = ScheduleGenerator.generate(
            classOfferingId: item.offeringId,
            scheduleCode: item.scheduleCode,
            firstDate: firstDate,
            lessonCount: item.lessonCount,
          );
        }

        // Tự động đồng bộ lên Google Sheet qua backend (xóa sheet cũ và chờ đồng bộ hoàn tất)
        String? syncError;
        try {
          await _scheduleApiClient.saveSchedules(
            importedClasses: classesForSchedule,
            schedules: schedules,
            clearPrevious: true,
          );
        } catch (e) {
          syncError = e.toString();
        }

        if (!mounted) return;

        // Chuyển sang màn hình Lịch Giảng Dạy ngay lập tức
        AppNavigationController.instance.openScheduleWithClasses(
          classes: classesForSchedule,
          schedules: schedules,
          semesterStart: semesterStart,
        );

        final hasShell =
            context.findAncestorStateOfType<State<AppShell>>() != null;
        if (!hasShell) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ScheduleGeneratorScreen(
                importedClasses: classesForSchedule,
                initialSchedules: schedules,
                semesterStart: semesterStart,
              ),
            ),
          );
        }

        if (!mounted) return;

        if (syncError != null) {
          M1SnackBar.show(
            context,
            'Đã nạp lịch vào hệ thống. Lỗi đồng bộ Google Sheet: $syncError',
            type: M1NoticeType.warning,
          );
        } else {
          M1SnackBar.show(
            context,
            'Đã nhập Markbook và tự động đồng bộ ${classesForSchedule.length} lớp lên Google Sheet.',
          );
        }
      }
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

  // 100% Exact Notion Tokens from ai/DESIGN.md
  static const _canvasBg = NotionColors.canvasSoft; // #F6F5F4
  static const _borderColor = NotionColors.hairline; // #E6E6E6
  static const _textPrimary = NotionColors.ink; // #000000
  static const _textSecondary = NotionColors.inkMuted; // #615D59

  @override
  Widget build(BuildContext context) {
    final selected = _selectedClass;
    return Scaffold(
      backgroundColor: _canvasBg,
      body: WorkspacePage(
        header: [
          _header(),
          if (_savedScheduleCheckFailed)
            Text(
              'Chưa kết nối được dữ liệu đã lưu. Bạn vẫn có thể xem lớp hiện hành.',
              style: const TextStyle(fontSize: 12, color: _textSecondary),
            ),
          if (_loadError != null) _Banner(message: _loadError!),
        ],
        body: _result == null
            ? _EmptyState(
                isLoading: _isLoading,
                onPickFile: _isLoading ? null : _pickFile,
                onLoadSaved: _isLoadingSavedSchedules
                    ? null
                    : _loadSavedClassesIntoView,
                savedCount: _savedScheduleCount,
              )
            : LayoutBuilder(
                builder: (context, size) {
                  if (size.maxWidth < 900) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: _selectedIndex,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Lớp Học Phần',
                          ),
                          items: List.generate(_result!.classes.length, (i) {
                            final c =
                                _editedClasses[_result!.classes[i]] ??
                                _result!.classes[i];
                            return DropdownMenuItem(
                              value: i,
                              child: Text(
                                '${c.subjectCode} · ${c.classCode}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                          onChanged: (i) {
                            if (i != null) _selectClass(i);
                          },
                        ),
                        const SizedBox(height: 12),
                        if (selected != null)
                          Expanded(child: _preview(selected)),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 240, child: _classList()),
                      const SizedBox(width: 20),
                      if (selected != null) Expanded(child: _preview(selected)),
                    ],
                  );
                },
              ),
        compactBodyHeight: 720,
      ),
    );
  }

  Widget _header() => WorkspaceHeader(
    icon: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1EF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.school_outlined,
        size: 18,
        color: NotionColors.ink,
      ),
    ),
    title: 'Danh Sách Lớp',
    subtitle: _result == null
        ? 'Nhập Markbook để quản lý lớp học và danh sách sinh viên.'
        : '${_result!.classes.length} lớp học phần · ${_result!.totalStudents} sinh viên',
    actions: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: NotionColors.ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: _isLoading ? null : _pickFile,
          child: Text(
            _isLoading ? 'Đang Nhập…' : 'Nhập Markbook',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Thao Tác Danh Sách Lớp',
          onSelected: (value) {
            if (value == 'reload') _loadSavedClassesIntoView();
            if (value == 'schedule') _openSavedSchedules();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'reload',
              enabled: !_isLoadingSavedSchedules,
              child: const Text('Tải Lại Danh Sách'),
            ),
            PopupMenuItem(
              value: 'schedule',
              enabled: !_isLoadingSavedSchedules,
              child: const Text('Xem Lịch Đã Lưu'),
            ),
          ],
        ),
      ],
    ),
  );

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
        color: NotionColors.surface,
        borderRadius: NotionRounded.md,
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: NotionElevation.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Text(
                  'DANH SÁCH LỚP (${allClasses.length})',
                  style: NotionTypography.eyebrow(color: _textSecondary),
                ),
              ],
            ),
          ),
          // Search box for classes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: NotionColors.canvasSoft,
                borderRadius: NotionRounded.xs,
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 14, color: _textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _classSearchController,
                      onChanged: (val) =>
                          setState(() => _classSearchQuery = val),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: _textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Lọc lớp hoặc môn…',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
                        ),
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
                      child: const Icon(
                        Icons.close,
                        size: 12,
                        color: _textSecondary,
                      ),
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
                final errors = currentItem.issues
                    .where((issue) => issue.isError)
                    .length;
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
                    borderRadius: NotionRounded.sm,
                    onTap: () =>
                        _selectClass(originalIndex >= 0 ? originalIndex : 0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFEBEAE7)
                            : (isHovered
                                  ? NotionColors.canvasSoft
                                  : Colors.transparent),
                        borderRadius: NotionRounded.sm,
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
                                ? NotionColors.accentOrange
                                : NotionColors.accentGreen,
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
                              border: Border.all(
                                color: _borderColor,
                                width: 0.8,
                              ),
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
    final query = _studentSearchQuery.trim().toLowerCase();
    final students = importedClass.students
        .where(
          (s) =>
              query.isEmpty ||
              '${s.rollNumber} ${s.fullName} ${s.email} ${s.memberCode}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: NotionColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _borderColor, width: 1),
            boxShadow: NotionElevation.soft,
          ),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _metadataField('Mã Lịch', _scheduleCodeController, 100),
                    _metadataField('Môn', _subjectCodeController, 130),
                    _metadataField('Lớp', _classCodeController, 130),
                    _metadataField('Số Buổi', _lessonCountController, 100),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
                onPressed: _confirmSelectedClass,
                child: Text(
                  'Xác Nhận',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Thao Tác Lớp',
                onSelected: (v) {
                  if (v == 'schedule') _continueToSchedule();
                  if (v == 'remove') _removeClass(_selectedIndex);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'schedule',
                    child: Text('Tạo / Xem Lịch Giảng Dạy'),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Bỏ Lớp Khỏi Danh Sách Nhập'),
                  ),
                ],
                icon: const Icon(Icons.more_vert, size: 20, color: NotionColors.ink),
              ),
            ],
          ),
        ),
        if (importedClass.issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 100),
            child: SingleChildScrollView(child: _issues(importedClass.issues)),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Sinh Viên · ${students.length}/${importedClass.students.length}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            SizedBox(
              width: 380,
              child: WorkspaceSearch(
                controller: _studentSearchController,
                onChanged: (v) => setState(() => _studentSearchQuery = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, size) {
              final width = size.maxWidth < 850 ? 850.0 : size.maxWidth;
              final widths = <int, TableColumnWidth>{
                0: const FixedColumnWidth(48),
                1: const FixedColumnWidth(100),
                2: const FlexColumnWidth(1.3),
                3: const FlexColumnWidth(1.8),
                4: const FlexColumnWidth(1.1),
                5: const FixedColumnWidth(85),
              };
              Widget cell(String text, {bool header = false}) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Tooltip(
                  message: text,
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: header ? _textSecondary : _textPrimary,
                      fontWeight: header ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              );
              return Container(
                decoration: BoxDecoration(
                  color: NotionColors.surface,
                  border: Border.all(color: _borderColor),
                  borderRadius: NotionRounded.md,
                  boxShadow: NotionElevation.soft,
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  controller: _rosterHorizontalScrollController,
                  thumbVisibility: true,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _rosterHorizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          Table(
                            columnWidths: widths,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(
                                  color: NotionColors.canvasSoft,
                                ),
                                children: [
                                  '#',
                                  'MSSV',
                                  'Họ Và Tên',
                                  'Email',
                                  'Mã FAP',
                                  'Lớp',
                                ].map((s) => cell(s, header: true)).toList(),
                              ),
                            ],
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: students.isEmpty
                                ? const Center(
                                    child: Text('Không Tìm Thấy Sinh Viên'),
                                  )
                                : Scrollbar(
                                    controller: _rosterVerticalScrollController,
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      controller:
                                          _rosterVerticalScrollController,
                                      itemCount: students.length,
                                      itemBuilder: (_, i) {
                                        final s = students[i];
                                        return Table(
                                          columnWidths: widths,
                                          children: [
                                            TableRow(
                                              decoration: const BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: Color(0xFFEDECE9),
                                                    width: 0.5,
                                                  ),
                                                ),
                                              ),
                                              children: [
                                                '${i + 1}',
                                                s.rollNumber,
                                                s.fullName,
                                                s.email,
                                                s.memberCode,
                                                s.classCode,
                                              ].map((s) => cell(s)).toList(),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                  style: GoogleFonts.inter(fontSize: 12, color: _textPrimary),
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
    height: 38,
    child: TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      style: GoogleFonts.inter(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: _textPrimary,
      ),
      decoration: InputDecoration(
        labelText: '$label *',
        labelStyle: GoogleFonts.inter(fontSize: 11, color: _textSecondary, fontWeight: FontWeight.w500),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: NotionColors.canvasSoft,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _textPrimary, width: 1.2),
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPickFile;
  final VoidCallback? onLoadSaved;
  final int? savedCount;

  const _EmptyState({
    this.isLoading = false,
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
            alignment: Alignment.center,
            child: const Icon(
              Icons.upload_file_outlined,
              size: 28,
              color: NotionColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Chưa có dữ liệu danh sách lớp',
            style: NotionTypography.heading3(color: NotionColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Chọn tệp Markbook (.xlsx, .ods) hoặc tải từ các lớp đã lưu trong CSDL.',
            textAlign: TextAlign.center,
            style: NotionTypography.bodySm(color: NotionColors.inkMuted),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
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
                onPressed: onPickFile,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file, size: 16),
                label: Text(
                  isLoading ? 'Đang nạp & đồng bộ...' : 'Chọn Markbook',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if ((savedCount ?? 0) > 0) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NotionColors.ink,
                    side: const BorderSide(color: NotionColors.hairline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  onPressed: onLoadSaved,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    'Tải $savedCount lớp đã lưu',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
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
