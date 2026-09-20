import 'package:flutter/material.dart';
import '../models/attendance_model.dart';

/// Bảng danh sách sinh viên kèm thanh tìm kiếm & Nút sửa tay A/P (DES-05, FR-14)
class StudentAttendanceTable extends StatefulWidget {
  final List<StudentAttendanceRecord> students;
  final Function(StudentAttendanceRecord student, String newStatus)
  onStatusChanged;
  final bool isUpdating;
  const StudentAttendanceTable({
    super.key,
    required this.students,
    required this.onStatusChanged,
    this.isUpdating = false,
  });
  @override
  State<StudentAttendanceTable> createState() => _StudentAttendanceTableState();
}

class _StudentAttendanceTableState extends State<StudentAttendanceTable> {
  String _searchQuery = '';
  @override
  Widget build(BuildContext context) {
    final filteredStudents = widget.students.where((s) {
      final q = _searchQuery.toLowerCase();
      return s.fullName.toLowerCase().contains(q) ||
          s.rollNumber.toLowerCase().contains(q) ||
          s.email.toLowerCase().contains(q);
    }).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(
                  Icons.people_outline_rounded,
                  color: Color(0xFF2563EB),
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Danh Sách Điểm Danh Chi Tiết',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 320,
                  height: 40,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Tìm theo Tên, MSSV, Email...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          // Data Table
          if (filteredStudents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(
                child: Text(
                  'Không có dữ liệu sinh viên phù hợp.',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                horizontalMargin: 16,
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF8FAFC),
                ),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF475569),
                  fontSize: 13,
                ),
                dataRowMinHeight: 52,
                dataRowMaxHeight: 56,
                columns: const [
                  DataColumn(
                    columnWidth: FixedColumnWidth(54),
                    label: Flexible(
                      child: Text(
                        'STT',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  DataColumn(
                    columnWidth: FixedColumnWidth(110),
                    label: Flexible(
                      child: Text(
                        'MSSV',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  DataColumn(
                    columnWidth: FixedColumnWidth(180),
                    label: Flexible(
                      child: Text(
                        'Họ và Tên',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  DataColumn(
                    columnWidth: FixedColumnWidth(230),
                    label: Flexible(
                      child: Text(
                        'Email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  DataColumn(
                    columnWidth: FixedColumnWidth(120),
                    label: Flexible(
                      child: Text(
                        'Trạng thái',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  DataColumn(
                    columnWidth: FixedColumnWidth(110),
                    label: Flexible(
                      child: Text(
                        'Nguồn gốc',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  DataColumn(
                    columnWidth: FixedColumnWidth(120),
                    label: Flexible(
                      child: Text(
                        'Thao tác',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                ],
                rows: List<DataRow>.generate(filteredStudents.length, (index) {
                  final s = filteredStudents[index];
                  final isP = s.isPresent;
                  final isA = s.isAbsent;
                  return DataRow(
                    color: WidgetStateProperty.resolveWith<Color>((states) {
                      if (isP) return const Color(0xFFF0FDF4); // Nền xanh nhạt
                      if (isA) return const Color(0xFFFEF2F2); // Nền đỏ nhạt
                      return Colors.white;
                    }),
                    cells: [
                      DataCell(
                        Text(
                          '${index + 1}',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                      DataCell(
                        Text(
                          s.rollNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          s.fullName,
                          style: const TextStyle(color: Color(0xFF1E293B)),
                        ),
                      ),
                      DataCell(
                        Text(
                          s.email,
                          style: const TextStyle(color: Color(0xFF475569)),
                        ),
                      ),
                      DataCell(_buildStatusBadge(s)),
                      DataCell(_buildNoteBadge(s.isManualEdited)),
                      DataCell(_buildActionButton(s)),
                    ],
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(StudentAttendanceRecord s) {
    if (s.isPresent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: Color(0xFF15803D),
            ),
            SizedBox(width: 4),
            Text(
              'Có mặt (P)',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else if (s.isAbsent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_rounded, size: 14, color: Color(0xFFB91C1C)),
            SizedBox(width: 4),
            Text(
              'Vắng (A)',
              style: TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return const Text('—', style: TextStyle(color: Color(0xFF94A3B8)));
  }

  Widget _buildNoteBadge(bool isManual) {
    if (isManual) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFFB45309)),
            SizedBox(width: 4),
            Text(
              'GV sửa tay',
              style: TextStyle(
                color: Color(0xFFB45309),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return const Text(
      'Quét QR',
      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
    );
  }

  Widget _buildActionButton(StudentAttendanceRecord s) {
    final nextStatus = s.isPresent ? 'A' : 'P';
    final isSwitchToP = nextStatus == 'P';
    return OutlinedButton.icon(
      onPressed: widget.isUpdating
          ? null
          : () => widget.onStatusChanged(s, nextStatus),
      icon: Icon(
        isSwitchToP ? Icons.check_rounded : Icons.close_rounded,
        size: 14,
      ),
      label: Text(isSwitchToP ? 'Đổi sang P' : 'Đổi sang A'),
      style: OutlinedButton.styleFrom(
        foregroundColor: isSwitchToP
            ? const Color(0xFF059669)
            : const Color(0xFFDC2626),
        side: BorderSide(
          color: isSwitchToP
              ? const Color(0xFF86EFAC)
              : const Color(0xFFFCA5A5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
