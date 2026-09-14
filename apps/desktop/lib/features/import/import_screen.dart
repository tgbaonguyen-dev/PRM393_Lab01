import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../schedule/schedule_generator_screen.dart';
import 'models/import_models.dart';
import 'services/markbook_parser.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _parser = MarkbookParser();
  final _scheduleCodeController = TextEditingController();
  final _subjectCodeController = TextEditingController();
  final _classCodeController = TextEditingController();
  final _lessonCountController = TextEditingController(text: '20');
  WorkbookImportResult? _result;
  final Map<String, ImportedClass> _editedClasses = {};
  final Set<String> _specialLessonCountSheets = {};
  int _selectedIndex = 0;
  bool _isLoading = false;
  String? _loadError;

  ImportedClass? get _selectedClass {
    final classes = _result?.classes ?? const <ImportedClass>[];
    if (classes.isEmpty) return null;
    final original = classes[_selectedIndex];
    return _editedClasses[original.sourceSheetName] ?? original;
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
    await _pickAndLoad(singleClassOnly: false);
  }

  Future<void> _pickSingleClassFile() async {
    await _pickAndLoad(singleClassOnly: true);
  }

  Future<void> _pickAndLoad({required bool singleClassOnly}) async {
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
      if (singleClassOnly && result.classes.length != 1) {
        throw const FormatException(
          'Tệp thêm riêng phải chứa đúng 1 sheet/lớp.',
        );
      }
      final existing = _result?.classes ?? const <ImportedClass>[];
      if (singleClassOnly &&
          existing.any((item) {
            final incoming = result.classes.single;
            return item.sourceSheetName == incoming.sourceSheetName ||
                (item.subjectCode == incoming.subjectCode &&
                    item.classCode == incoming.classCode);
          })) {
        throw const FormatException(
          'Lớp này đã tồn tại trong danh sách import.',
        );
      }
      final combined = singleClassOnly && _result != null
          ? WorkbookImportResult(
              sourceFileName:
                  '${_result!.sourceFileName}, ${result.sourceFileName}',
              classes: [...existing, ...result.classes],
            )
          : result;
      setState(() {
        _result = combined;
        final previousEdits = singleClassOnly
            ? Map<String, ImportedClass>.of(_editedClasses)
            : <String, ImportedClass>{};
        final previousSpecialSheets = singleClassOnly
            ? Set<String>.of(_specialLessonCountSheets)
            : <String>{};
        _editedClasses
          ..clear()
          ..addEntries(
            combined.classes.map(
              (item) => MapEntry(
                item.sourceSheetName,
                previousEdits[item.sourceSheetName] ?? item,
              ),
            ),
          );
        _specialLessonCountSheets
          ..clear()
          ..addAll(previousSpecialSheets);
        if (singleClassOnly) {
          _specialLessonCountSheets.add(result.classes.single.sourceSheetName);
        }
        _selectedIndex = singleClassOnly ? combined.classes.length - 1 : 0;
        if (combined.classes.isNotEmpty) {
          _loadMetadata(combined.classes[_selectedIndex]);
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
      _loadMetadata(_editedClasses[original.sourceSheetName] ?? original);
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
    _editedClasses[importedClass.sourceSheetName] = importedClass.copyWith(
      scheduleCode: _scheduleCodeController.text.trim(),
      subjectCode: _subjectCodeController.text.trim().toUpperCase(),
      classCode: _classCodeController.text.trim().toUpperCase(),
      lessonCount: _isSpecialLessonCountClass(importedClass)
          ? int.tryParse(_lessonCountController.text.trim()) ?? 0
          : ImportedClass.defaultLessonCountFor(
              _subjectCodeController.text.trim(),
            ),
    );
  }

  bool _isSpecialLessonCountClass(ImportedClass importedClass) =>
      _specialLessonCountSheets.contains(importedClass.sourceSheetName);

  List<ImportedClass>? _prepareAllClasses() {
    _storeSelectedMetadata();
    final result = _result;
    if (result == null) return null;
    final prepared = result.classes
        .map((original) {
          final edited = _editedClasses[original.sourceSheetName] ?? original;
          final issues = edited.issues.where((issue) {
            return !const {
              'invalid_schedule_code',
              'missing_subject_code',
              'class_conflict',
            }.contains(issue.code);
          }).toList();
          return edited.copyWith(issues: issues);
        })
        .toList(growable: false);

    final invalidCount = prepared.where((item) {
      final metadataValid =
          RegExp(r'^[123][1-8]$').hasMatch(item.scheduleCode) &&
          item.subjectCode.trim().isNotEmpty &&
          item.classCode.trim().isNotEmpty;
      final lessonCountValid = item.lessonCount >= 1 && item.lessonCount <= 60;
      return !metadataValid ||
          !lessonCountValid ||
          item.issues.any((issue) => issue.isError);
    }).length;
    if (invalidCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Còn $invalidCount lớp chưa hợp lệ. Hãy kiểm tra mã lịch, metadata, dữ liệu và số buổi môn đặc biệt (1–60).',
          ),
        ),
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
        title: const Text('PRM393 • Nhập Markbook'),
        backgroundColor: Colors.white,
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
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickSingleClassFile,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Thêm môn đặc biệt'),
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
                final item =
                    _editedClasses[original.sourceSheetName] ?? original;
                final errors = item.issues
                    .where((issue) => issue.isError)
                    .length;
                return ListTile(
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
                  trailing: Text(item.scheduleCode),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(ImportedClass importedClass) {
    final isSpecialLessonCount = _isSpecialLessonCountClass(importedClass);
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
                      if (isSpecialLessonCount)
                        _metadataField(
                          'Số buổi đặc biệt',
                          _lessonCountController,
                          145,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
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
            if (isSpecialLessonCount) ...[
              const SizedBox(height: 8),
              Text(
                'Môn này được thêm riêng nên có thể đặt số buổi khác mặc định. Mã PRN mặc định 22 buổi, môn khác mặc định 20 buổi.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
