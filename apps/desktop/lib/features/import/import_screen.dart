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
  final _semesterController = TextEditingController();
  WorkbookImportResult? _result;
  int _selectedIndex = 0;
  bool _isLoading = false;
  String? _loadError;

  ImportedClass? get _selectedClass {
    final classes = _result?.classes ?? const <ImportedClass>[];
    return classes.isEmpty ? null : classes[_selectedIndex];
  }

  @override
  void dispose() {
    _scheduleCodeController.dispose();
    _subjectCodeController.dispose();
    _classCodeController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
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
      setState(() {
        _result = result;
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
    setState(() {
      _selectedIndex = index;
      _loadMetadata(_result!.classes[index]);
    });
  }

  void _loadMetadata(ImportedClass importedClass) {
    _scheduleCodeController.text = importedClass.scheduleCode;
    _subjectCodeController.text = importedClass.subjectCode;
    _classCodeController.text = importedClass.classCode;
    _semesterController.text = importedClass.semester;
  }

  void _continueToSchedule() {
    final importedClass = _selectedClass;
    if (importedClass == null) return;
    final scheduleCode = _scheduleCodeController.text.trim();
    final subjectCode = _subjectCodeController.text.trim().toUpperCase();
    final classCode = _classCodeController.text.trim().toUpperCase();
    final semester = _semesterController.text.trim().toUpperCase();
    final unresolvedIssues = importedClass.issues.where((issue) {
      return !const {
        'invalid_schedule_code',
        'missing_subject_code',
        'class_conflict',
        'class_from_roster',
      }.contains(issue.code);
    }).toList();
    final metadataValid =
        RegExp(r'^[123][1-4]$').hasMatch(scheduleCode) &&
        subjectCode.isNotEmpty &&
        classCode.isNotEmpty &&
        semester.isNotEmpty;
    if (unresolvedIssues.any((issue) => issue.isError) || !metadataValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !metadataValid
                ? 'Hãy nhập đúng mã lịch, môn, lớp và học kỳ.'
                : 'Markbook vẫn còn lỗi dữ liệu cần xử lý.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScheduleGeneratorScreen(
          importedClass: importedClass.copyWith(
            scheduleCode: scheduleCode,
            subjectCode: subjectCode,
            classCode: classCode,
            semester: semester,
            issues: unresolvedIssues,
          ),
        ),
      ),
    );
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
        child: Row(
          children: [
            const Icon(Icons.table_view_outlined, size: 38),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bước 1 — Nhập danh sách lớp',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
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
          ],
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
                final item = classes[index];
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
                      _metadataField('Học kỳ', _semesterController, 105),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _continueToSchedule,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Tạo lịch'),
                ),
              ],
            ),
            if (importedClass.issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              _issues(importedClass.issues),
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
