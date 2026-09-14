import 'package:flutter/material.dart';
import '../models/attendance_model.dart';

/// Thẻ đếm sĩ số thời gian thực chuẩn giao diện Slate/Blue (DES-03, FR-11)
class AttendanceSummaryCards extends StatelessWidget {
  final List<StudentAttendanceRecord> attendanceList;
  final bool isLive;
  const AttendanceSummaryCards({
    super.key,
    required this.attendanceList,
    this.isLive = true,
  });
  @override
  Widget build(BuildContext context) {
    final total = attendanceList.length;
    final present = attendanceList.where((s) => s.isPresent).length;
    final absent = attendanceList.where((s) => s.isAbsent).length;
    final rate = total > 0 ? (present / total * 100).toStringAsFixed(1) : '0.0';
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Có mặt (Present)',
            value: '$present',
            subtitle: '$rate% sĩ số',
            icon: Icons.check_circle_rounded,
            primaryColor: const Color(0xFF059669), // Emerald 600
            bgColor: const Color(0xFFECFDF5), // Emerald 50
            borderColor: const Color(0xFFA7F3D0),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'Vắng mặt (Absent)',
            value: '$absent',
            subtitle: 'Chưa check-in',
            icon: Icons.cancel_rounded,
            primaryColor: const Color(0xFFDC2626), // Red 600
            bgColor: const Color(0xFFFEF2F2), // Red 50
            borderColor: const Color(0xFFFECACA),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'Tổng sĩ số lớp',
            value: '$total',
            subtitle: isLive ? '● Live Polling (5s)' : 'Đã dừng sync',
            icon: Icons.people_alt_rounded,
            primaryColor: const Color(0xFF2563EB), // Blue 600
            bgColor: const Color(0xFFEFF6FF), // Blue 50
            borderColor: const Color(0xFFBFDBFE),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color primaryColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  fontFamily: 'Segoe UI',
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: primaryColor, size: 26),
          ),
        ],
      ),
    );
  }
}
