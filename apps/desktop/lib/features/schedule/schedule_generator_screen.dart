import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../import/models/import_models.dart';
import 'models/schedule_models.dart';
import 'services/schedule_api_client.dart';
import 'services/schedule_code_parser.dart';
import 'services/schedule_generator.dart';

class ScheduleGeneratorScreen extends StatefulWidget {
  final ImportedClass importedClass;
  final ScheduleApiClient? apiClient;

  const ScheduleGeneratorScreen({
    super.key,
    required this.importedClass,
    this.apiClient,
  });

  @override
  State<ScheduleGeneratorScreen> createState() =>
      _ScheduleGeneratorScreenState();
}

class _ScheduleGeneratorScreenState extends State<ScheduleGeneratorScreen> {
  late final ScheduleApiClient _apiClient;
  DateTime? _firstDate;
  List<ClassLesson> _lessons = const [];
  bool _isSaving = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ScheduleApiClient();
  }

  ScheduleRule get _rule =>
      ScheduleCodeParser.parse(widget.importedClass.scheduleCode);

  String get _weekdayLabel => _rule.weekdays
      .map(
        (weekday) => switch (weekday) {
          DateTime.monday => 'Thứ Hai',
          DateTime.tuesday => 'Thứ Ba',
          DateTime.wednesday => 'Thứ Tư',
          DateTime.thursday => 'Thứ Năm',
          DateTime.friday => 'Thứ Sáu',
          DateTime.saturday => 'Thứ Bảy',
          _ => 'Chủ Nhật',
        },
      )
      .join(' và ');

  String _dayName(DateTime date) => switch (date.weekday) {
    DateTime.monday => 'Thứ Hai',
    DateTime.tuesday => 'Thứ Ba',
    DateTime.wednesday => 'Thứ Tư',
    DateTime.thursday => 'Thứ Năm',
    DateTime.friday => 'Thứ Sáu',
    DateTime.saturday => 'Thứ Bảy',
    _ => 'Chủ Nhật',
  };

  Future<void> _chooseFirstDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _firstDate = picked;
      _lessons = const [];
      _message = null;
    });
  }

  void _generate() {
    final firstDate = _firstDate;
    if (firstDate == null) {
      _showMessage('Hãy chọn ngày bắt đầu.', isError: true);
      return;
    }
    try {
      final lessons = ScheduleGenerator.generate(
        classOfferingId: widget.importedClass.offeringId,
        scheduleCode: widget.importedClass.scheduleCode,
        firstDate: firstDate,
      );
      setState(() {
        _lessons = lessons;
        _message =
            'Đã sinh đủ 20 buổi. Hãy kiểm tra và chỉnh ngày nghỉ/học bù nếu cần.';
        _messageIsError = false;
      });
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Invalid argument(s): ', ''),
        isError: true,
      );
    }
  }

  Future<void> _editLesson(ClassLesson lesson) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: lesson.date,
      firstDate: DateTime(lesson.date.year - 1),
      lastDate: DateTime(lesson.date.year + 1, 12, 31),
    );
    if (picked == null) return;
    try {
      final updated = ScheduleGenerator.replaceLessonDate(
        lessons: _lessons,
        sequenceNumber: lesson.sequenceNumber,
        newDate: picked,
      );
      setState(() {
        _lessons = updated;
        _message = 'Đã điều chỉnh buổi ${lesson.sequenceNumber}.';
        _messageIsError = false;
      });
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Invalid argument(s): ', ''),
        isError: true,
      );
    }
  }

  Future<void> _save() async {
    if (_lessons.length != ScheduleGenerator.lessonCount) return;
    setState(() => _isSaving = true);
    try {
      final message = await _apiClient.saveSchedule(
        importedClass: widget.importedClass,
        lessons: _lessons,
      );
      _showMessage(message, isError: false);
    } catch (error) {
      _showMessage('Không thể lưu lịch: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PRM393 • Sinh lịch 20 buổi'),
        backgroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _setupCard(),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _messageBanner(),
            ],
            const SizedBox(height: 16),
            Expanded(child: _lessons.isEmpty ? _emptyState() : _lessonTable()),
          ],
        ),
      ),
    );
  }

  Widget _setupCard() => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.importedClass.subjectCode} • ${widget.importedClass.classCode}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.importedClass.semester} • Mã ${_rule.code} • $_weekdayLabel',
                ),
                Text(
                  'Ca ${_rule.dailySlot}: ${_rule.startTime}–${_rule.endTime}',
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _chooseFirstDate,
            icon: const Icon(Icons.calendar_month),
            label: Text(
              _firstDate == null
                  ? 'Chọn ngày bắt đầu'
                  : DateFormat('dd/MM/yyyy').format(_firstDate!),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Sinh 20 buổi'),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            onPressed: _lessons.length == 20 && !_isSaving ? _save : null,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Đang lưu...' : 'Lưu lịch'),
          ),
        ],
      ),
    ),
  );

  Widget _messageBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _messageIsError ? Colors.red.shade50 : Colors.green.shade50,
      border: Border.all(
        color: _messageIsError ? Colors.red.shade200 : Colors.green.shade200,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(_message!),
  );

  Widget _emptyState() => const Card(
    elevation: 0,
    child: Center(
      child: Text(
        'Chọn ngày bắt đầu để tạo lịch. Ngày phải đúng cặp thứ của mã lịch.',
      ),
    ),
  );

  Widget _lessonTable() => Card(
    elevation: 0,
    child: SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Buổi')),
            DataColumn(label: Text('Ngày')),
            DataColumn(label: Text('Thứ')),
            DataColumn(label: Text('Ca học')),
            DataColumn(label: Text('Trạng thái')),
            DataColumn(label: Text('Điều chỉnh')),
          ],
          rows: _lessons
              .map(
                (lesson) => DataRow(
                  cells: [
                    DataCell(
                      Text(lesson.sequenceNumber.toString().padLeft(2, '0')),
                    ),
                    DataCell(
                      Text(DateFormat('dd/MM/yyyy').format(lesson.date)),
                    ),
                    DataCell(Text(_dayName(lesson.date))),
                    DataCell(
                      Text(
                        'Ca ${lesson.dailySlot} • ${lesson.startTime}–${lesson.endTime}',
                      ),
                    ),
                    DataCell(
                      lesson.isAdjusted
                          ? const Chip(label: Text('Đã chỉnh'))
                          : const Text('Theo lịch'),
                    ),
                    DataCell(
                      IconButton(
                        tooltip: 'Sửa ngày nghỉ/học bù',
                        icon: const Icon(Icons.edit_calendar_outlined),
                        onPressed: () => _editLesson(lesson),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}
