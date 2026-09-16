import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../schedule/schedule_generator_screen.dart';
import '../schedule/services/schedule_api_client.dart';
import '../../shared/m1_snackbar.dart';
import 'models/import_models.dart';
import 'services/markbook_import_merger.dart';
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
    super.dispose();
  }

  Future<void> _pickFile() async {
    await _pickAndLoad();
  }

  bool _hasAutoLoadedSavedSchedules = false;

  @override
  void initState() {
    super.initState();
    _refreshSavedScheduleCount(autoOpen: true);
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
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScheduleGeneratorScreen(
            importedClasses: saved.classes,
            initialSchedules: saved.schedules,
            semesterStart: saved.firstLessonDate,
          ),
        ),
      );
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
      final result = await _parser.parseFile(File(path));
      if (!mounted) return;
      final previous = _result;
      final previousClasses = previous?.classes
          .map((item) => _editedClasses[item] ?? item)
          .toList(growable: false);
      final merged = mergeMarkbookImports(
        previous == null
            ? null
            : WorkbookImportResult(
                sourceFileName: previous.sourceFileName,
                classes: previousClasses!,
              ),
        result,
      );
      final previousCount = previous?.classes.length ?? 0;
      setState(() {
        _result = merged;
        _editedClasses
          ..clear()
          ..addEntries(merged.classes.map((item) => MapEntry(item, item)));
        _selectedIndex = merged.classes.isEmpty
            ? 0
            : previousCount.clamp(0, merged.classes.length - 1);
        if (merged.classes.isNotEmpty) {
          _loadMetadata(merged.classes[_selectedIndex]);
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
    final original = _result!.classes[_selectedIndex];
    _editedClasses[original] = importedClass.copyWith(
      scheduleCode: _scheduleCodeController.text.trim(),
      subjectCode: _subjectCodeController.text.trim().toUpperCase(),
      classCode: _classCodeController.text.trim().toUpperCase(),
      lessonCount: int.tryParse(_lessonCountController.text.trim()) ?? 0,
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
    final validated = _validateClassMetadata(importedClass);
    setState(() {
      final original = _result!.classes[_selectedIndex];
      _editedClasses[original] = validated;
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
    final prepared = result.classes
        .map((original) {
          final edited = _editedClasses[original] ?? original;
          return _validateClassMetadata(edited);
        })
        .toList(growable: false);

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

  String _semesterCodeFor(DateTime start) {
    final prefix = switch (start.month) {
      <= 4 => 'SP',
      <= 8 => 'SU',
      _ => 'FA',
    };
    return '$prefix${(start.year % 100).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedClass = _selectedClass;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhập Markbook'),
        backgroundColor: const Color(0xFFE0F2FE),
        foregroundColor: const Color(0xFF1D4ED8),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 18),
            if (_loadError != null) ...[
              _Banner(message: _loadError!),
              const SizedBox(height: 12),
            ],
            if (_result == null)
              const Expanded(child: _EmptyState())
            else
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 290, child: _classList()),
                    const SizedBox(width: 18),
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
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heading = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.table_view_outlined, size: 38),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bước 1 — Nhập danh sách lớp',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result == null
                            ? 'Chọn tệp .xlsx hoặc .ods. Tệp nguồn chỉ được đọc.'
                            : '${result.sourceFileName} • ${result.classes.length} lớp • ${result.totalStudents} sinh viên',
                      ),
                    ],
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isLoading ? null : _pickFile,
                  icon: _isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(_isLoading ? 'Đang đọc...' : 'Chọn Markbook'),
                ),
                if (_isLoadingSavedSchedules)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Đang kiểm tra lịch đã lưu...'),
                  )
                else if ((_savedScheduleCount ?? 0) > 0)
                  OutlinedButton.icon(
                    onPressed: _isLoadingSavedSchedules
                        ? null
                        : _openSavedSchedules,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _isLoadingSavedSchedules
                          ? 'Đang tải lịch...'
                          : 'Mở lịch đã lưu ($_savedScheduleCount lớp)',
                    ),
                  )
                else if (_savedScheduleCheckFailed)
                  Tooltip(
                    message:
                        _savedScheduleCheckError ??
                        'Backend không phản hồi tại 127.0.0.1:8080.',
                    child: OutlinedButton.icon(
                      onPressed: _refreshSavedScheduleCount,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Backend lỗi — thử kiểm tra lại'),
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
      ),
    );
  }

  Widget _classList() {
    final classes = _result!.classes;
    return Card(
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Sheet / lớp phát hiện',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: classes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, index) {
                final original = classes[index];
                final item = _editedClasses[original] ?? original;
                final errors = item.issues
                    .where((issue) => issue.isError)
                    .length;
                final isHovered = identical(_hoveredClass, original);
                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredClass = original),
                  onExit: (_) {
                    if (identical(_hoveredClass, original)) {
                      setState(() => _hoveredClass = null);
                    }
                  },
                  child: ListTile(
                    selected: index == _selectedIndex,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onTap: () => _selectClass(index),
                    leading: Icon(
                      errors > 0
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: errors > 0 ? Colors.red : Colors.green,
                    ),
                    title: Text(
                      item.subjectCode.isEmpty
                          ? item.sourceSheetName
                          : item.subjectCode,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${item.classCode.isEmpty ? 'Chưa rõ lớp' : item.classCode} • ${item.students.length} SV',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.scheduleCode),
                        AnimatedOpacity(
                          opacity: isHovered ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: IgnorePointer(
                            ignoring: !isHovered,
                            child: IconButton(
                              tooltip: 'Xóa lớp này',
                              onPressed: () => _removeClass(index),
                              icon: const Icon(Icons.close, color: Colors.red),
                            ),
                          ),
                        ),
                      ],
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
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      _metadataField('Số buổi', _lessonCountController, 120),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _confirmSelectedClass,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Xác nhận lớp'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _continueToSchedule,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Tiếp tục: Xem lịch giảng dạy'),
                ),
              ],
            ),
            if (importedClass.issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              _issues(importedClass.issues),
            ],
            const SizedBox(height: 8),
            Text(
              'Mã PRN mặc định 22 buổi, môn khác mặc định 20 buổi. Có thể điều chỉnh số buổi từ 1 đến 60 cho từng lớp.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Xem trước ${importedClass.students.length} sinh viên',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Class')),
                        DataColumn(label: Text('RollNumber')),
                        DataColumn(label: Text('FullName')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('MemberCode')),
                      ],
                      rows: importedClass.students
                          .map(
                            (student) => DataRow(
                              cells: [
                                DataCell(Text(student.classCode)),
                                DataCell(Text(student.rollNumber)),
                                DataCell(Text(student.fullName)),
                                DataCell(Text(student.email)),
                                DataCell(Text(student.memberCode)),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _issues(List<ImportValidationIssue> issues) {
    final errorCount = issues.where((issue) => issue.isError).length;
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text('$errorCount lỗi • ${issues.length - errorCount} cảnh báo'),
      children: issues
          .map(
            (issue) => ListTile(
              dense: true,
              leading: Icon(
                issue.isError ? Icons.error : Icons.warning_amber,
                color: issue.isError ? Colors.red : Colors.orange,
              ),
              title: Text(issue.message),
              subtitle: issue.rowNumber == null
                  ? null
                  : Text('Dòng ${issue.rowNumber}'),
            ),
          )
          .toList(),
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
      decoration: InputDecoration(labelText: '$label *', isDense: true),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.file_open_outlined, size: 70, color: Colors.blueGrey),
        SizedBox(height: 14),
        Text(
          'Chưa có Markbook',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text('Chọn tệp để xem trước danh sách lớp và kiểm tra dữ liệu.'),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  final String message;
  const _Banner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      border: Border.all(color: Colors.red.shade200),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(message),
  );
}
