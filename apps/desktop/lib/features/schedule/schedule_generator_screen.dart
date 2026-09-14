import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../import/models/import_models.dart';
import 'models/schedule_models.dart';
import 'services/schedule_api_client.dart';
import 'services/schedule_generator.dart';
import 'services/schedule_overview.dart';

class ScheduleGeneratorScreen extends StatefulWidget {
  final List<ImportedClass> importedClasses;
  final DateTime semesterStart;
  final int initialClassIndex;
  final ScheduleApiClient? apiClient;

  const ScheduleGeneratorScreen({
    super.key,
    required this.importedClasses,
    required this.semesterStart,
    this.initialClassIndex = 0,
    this.apiClient,
  }) : assert(importedClasses.length > 0);

  @override
  State<ScheduleGeneratorScreen> createState() =>
      _ScheduleGeneratorScreenState();
}

class _ScheduleGeneratorScreenState extends State<ScheduleGeneratorScreen> {
  static const _allClasses = '__all_classes__';
  static const _slotTimes = <int, (String, String)>{
    1: ('07:00', '09:15'),
    2: ('09:30', '11:45'),
    3: ('12:30', '14:45'),
    4: ('15:00', '17:15'),
  };
  static const _dayNames = <String>[
    'THỨ HAI',
    'THỨ BA',
    'THỨ TƯ',
    'THỨ NĂM',
    'THỨ SÁU',
    'THỨ BẢY',
    'CHỦ NHẬT',
  ];

  late final ScheduleApiClient _apiClient;
  late final List<ImportedClass> _classes;
  final Map<String, List<ClassLesson>> _schedules = {};
  late DateTime _weekStart;
  String _filter = _allClasses;
  String? _selectedKey;
  String? _confirmedKey;
  String? _suggestedKey;
  String? _message;
  bool _messageIsError = false;
  bool _isSaving = false;

  ScheduledLessonView? get _selectedLesson => ScheduleOverview.findByKey(
    key: _selectedKey,
    classes: _classes,
    schedules: _schedules,
  );

  String? get _classFilter => _filter == _allClasses ? null : _filter;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ScheduleApiClient();
    _classes = List<ImportedClass>.unmodifiable(widget.importedClasses);
    _weekStart = ScheduleOverview.startOfWeek(widget.semesterStart);
    _generateAllSchedules();

    final current = ScheduleOverview.findCurrentLesson(
      classes: _classes,
      schedules: _schedules,
      now: DateTime.now(),
    );
    if (current != null) {
      _suggestedKey = current.key;
      _selectedKey = current.key;
      _weekStart = ScheduleOverview.startOfWeek(current.lesson.date);
      return;
    }

    final index = widget.initialClassIndex.clamp(0, _classes.length - 1);
    final firstLessons = _schedules[_classes[index].sourceSheetName]!;
    if (firstLessons.isNotEmpty) {
      _weekStart = ScheduleOverview.startOfWeek(firstLessons.first.date);
    }
  }

  void _generateAllSchedules() {
    for (final importedClass in _classes) {
      final firstDate = ScheduleGenerator.firstTeachingDateOnOrAfter(
        scheduleCode: importedClass.scheduleCode,
        semesterStart: widget.semesterStart,
      );
      _schedules[importedClass.sourceSheetName] = ScheduleGenerator.generate(
        classOfferingId: importedClass.offeringId,
        scheduleCode: importedClass.scheduleCode,
        firstDate: firstDate,
        lessonCount: importedClass.lessonCount,
      );
    }
  }

  void _changeWeek(int weeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: weeks * 7));
    });
  }

  void _selectLesson(ScheduledLessonView item) {
    setState(() {
      _selectedKey = item.key;
      _confirmedKey = null;
      _message = null;
    });
  }

  void _confirmLesson() {
    final selected = _selectedLesson;
    if (selected == null) return;
    setState(() {
      _confirmedKey = selected.key;
      _message =
          'Đã xác nhận buổi ${selected.lesson.sequenceNumber} của ${selected.importedClass.subjectCode} - ${selected.importedClass.classCode}.';
      _messageIsError = false;
    });
  }

  Future<void> _editSelectedLesson() async {
    final selected = _selectedLesson;
    if (selected == null) return;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Chọn ngày nghỉ lễ hoặc học bù',
      initialDate: selected.lesson.date,
      firstDate: DateTime(selected.lesson.date.year - 1),
      lastDate: DateTime(selected.lesson.date.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    try {
      final classKey = selected.importedClass.sourceSheetName;
      final updated = ScheduleGenerator.replaceLessonDate(
        lessons: _schedules[classKey]!,
        sequenceNumber: selected.lesson.sequenceNumber,
        newDate: picked,
      );
      setState(() {
        _schedules[classKey] = updated;
        _weekStart = ScheduleOverview.startOfWeek(picked);
        _confirmedKey = null;
        _message = 'Đã điều chỉnh ngày buổi ${selected.lesson.sequenceNumber}.';
        _messageIsError = false;
      });
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Invalid argument(s): ', ''),
        isError: true,
      );
    }
  }

  Future<void> _saveSelectedClass() async {
    final selected = _selectedLesson;
    if (selected == null) return;
    setState(() => _isSaving = true);
    try {
      final message = await _apiClient.saveSchedule(
        importedClass: selected.importedClass,
        lessons: _schedules[selected.importedClass.sourceSheetName]!,
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
        title: const Text('PRM393 • Lịch giảng dạy'),
        backgroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(),
            const SizedBox(height: 12),
            _selectionPanel(),
            if (_message != null) ...[
              const SizedBox(height: 10),
              _messageBanner(),
            ],
            const SizedBox(height: 12),
            Expanded(child: _weeklyTable()),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final range =
        '${DateFormat('dd/MM').format(_weekStart)} – ${DateFormat('dd/MM').format(weekEnd)}';
    final totalLessons = _classes.fold<int>(
      0,
      (total, item) => total + item.lessonCount,
    );
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: const Icon(Icons.school_outlined, size: 18),
              label: Text('${_classes.length} lớp • $totalLessons buổi'),
            ),
            OutlinedButton(
              onPressed: () => _changeWeek(-1),
              child: const Icon(Icons.chevron_left),
            ),
            Chip(
              avatar: const Icon(Icons.calendar_view_week_outlined, size: 18),
              label: Text('Tuần $range • ${_weekStart.year}'),
            ),
            OutlinedButton(
              onPressed: () => _changeWeek(1),
              child: const Icon(Icons.chevron_right),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _weekStart = ScheduleOverview.startOfWeek(DateTime.now());
                });
              },
              icon: const Icon(Icons.today_outlined),
              label: const Text('Tuần hiện tại'),
            ),
            SizedBox(
              width: 245,
              child: DropdownButtonFormField<String>(
                initialValue: _filter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Lọc lớp',
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: _allClasses,
                    child: Text('Tất cả ${_classes.length} lớp'),
                  ),
                  ..._classes.map(
                    (item) => DropdownMenuItem(
                      value: item.sourceSheetName,
                      child: Text(
                        '${item.subjectCode} • ${item.classCode}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _filter = value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectionPanel() {
    final selected = _selectedLesson;
    return Card(
      elevation: 0,
      color: selected == null ? Colors.blueGrey.shade50 : Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  selected?.key == _suggestedKey
                      ? Icons.schedule
                      : Icons.info_outline,
                  color: selected?.key == _suggestedKey
                      ? Colors.green.shade700
                      : Colors.blueGrey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: selected == null
                      ? const Text(
                          'Không có buổi đang diễn ra. Hãy chọn một ô lịch để xác nhận buổi cần điểm danh.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selected.importedClass.subjectCode} • ${selected.importedClass.classCode} • Buổi ${selected.lesson.sequenceNumber}/${selected.importedClass.lessonCount}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${DateFormat('dd/MM/yyyy').format(selected.lesson.date)} • ${selected.lesson.startTime}–${selected.lesson.endTime}'
                              '${selected.key == _suggestedKey ? ' • Đang diễn ra' : ''}',
                            ),
                          ],
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: selected == null ? null : _editSelectedLesson,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Chỉnh ngày'),
                ),
                FilledButton.tonalIcon(
                  onPressed: selected == null ? null : _confirmLesson,
                  icon: Icon(
                    selected?.key == _confirmedKey
                        ? Icons.check_circle
                        : Icons.check,
                  ),
                  label: Text(
                    selected?.key == _confirmedKey
                        ? 'Đã xác nhận'
                        : 'Xác nhận buổi',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: selected == null || _isSaving
                      ? null
                      : _saveSelectedClass,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Đang lưu...' : 'Lưu lịch lớp'),
                ),
                Tooltip(
                  message: 'Thành viên 2 sẽ gắn màn hình mở phiên và QR.',
                  child: FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Mở điểm danh • Chờ M2'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _messageIsError ? Colors.red.shade50 : Colors.green.shade50,
      border: Border.all(
        color: _messageIsError ? Colors.red.shade200 : Colors.green.shade200,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(_message!),
  );

  Widget _weeklyTable() {
    final days = List.generate(
      7,
      (index) => _weekStart.add(Duration(days: index)),
    );
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < 1180
              ? 1180.0
              : constraints.maxWidth;
          return SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Table(
                  border: TableBorder.all(color: const Color(0xFFDCE3ED)),
                  columnWidths: const {
                    0: FixedColumnWidth(100),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                    3: FlexColumnWidth(),
                    4: FlexColumnWidth(),
                    5: FlexColumnWidth(),
                    6: FlexColumnWidth(),
                    7: FlexColumnWidth(),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFF2557A7)),
                      children: [
                        const _HeaderCell(title: 'CA / TUẦN'),
                        ...List.generate(
                          7,
                          (index) => _HeaderCell(
                            title: _dayNames[index],
                            subtitle: DateFormat('dd/MM').format(days[index]),
                          ),
                        ),
                      ],
                    ),
                    ...List.generate(4, (index) {
                      final slot = index + 1;
                      final time = _slotTimes[slot]!;
                      return TableRow(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? Colors.white
                              : const Color(0xFFF8FAFC),
                        ),
                        children: [
                          Container(
                            constraints: const BoxConstraints(minHeight: 120),
                            color: const Color(0xFFF1F5F9),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Slot $slot',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${time.$1}\n${time.$2}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...days.map((day) => _scheduleCell(day, slot)),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _scheduleCell(DateTime day, int slot) {
    final lessons = ScheduleOverview.lessonsForCell(
      classes: _classes,
      schedules: _schedules,
      date: day,
      dailySlot: slot,
      classFilter: _classFilter,
    );
    if (lessons.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('—', style: TextStyle(color: Color(0xFFCBD5E1))),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lessons.map(_lessonCard).toList(growable: false),
      ),
    );
  }

  Widget _lessonCard(ScheduledLessonView item) {
    final selected = item.key == _selectedKey;
    final suggested = item.key == _suggestedKey;
    final confirmed = item.key == _confirmedKey;
    final borderColor = suggested
        ? Colors.green
        : selected
        ? const Color(0xFF2563EB)
        : const Color(0xFFCBD5E1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? const Color(0xFFEFF6FF) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _selectLesson(item),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.importedClass.subjectCode,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (confirmed)
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.green,
                      ),
                  ],
                ),
                Text(
                  item.importedClass.classCode,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF2557A7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Buổi ${item.lesson.sequenceNumber.toString().padLeft(2, '0')} / ${item.importedClass.lessonCount}',
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  '${item.lesson.startTime}–${item.lesson.endTime}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _HeaderCell({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
      ],
    ),
  );
}
