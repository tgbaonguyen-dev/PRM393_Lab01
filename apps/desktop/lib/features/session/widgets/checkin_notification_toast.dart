import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/notion_tokens.dart';

/// Mô hình dữ liệu một thông báo sinh viên vừa điểm danh
class CheckinNotificationItem {
  final String id;
  final String fullName;
  final String rollNumber;
  final String email;
  final DateTime timestamp;

  const CheckinNotificationItem({
    required this.id,
    required this.fullName,
    required this.rollNumber,
    required this.email,
    required this.timestamp,
  });
}

/// Toast thông báo sinh viên điểm danh chuẩn Notion Analysis
class CheckinNotificationToast extends StatelessWidget {
  final CheckinNotificationItem item;
  final VoidCallback onDismiss;

  const CheckinNotificationToast({
    super.key,
    required this.item,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = item.fullName.trim().isNotEmpty ? item.fullName : item.email;
    final displayRoll = item.rollNumber.trim().isNotEmpty ? item.rollNumber : '';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: NotionColors.surface,
          borderRadius: NotionRounded.md,
          border: Border.all(color: NotionColors.hairline, width: 1),
          boxShadow: NotionElevation.soft,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge Vừa Có Mặt
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: NotionColors.tagGreenBg,
                borderRadius: NotionRounded.xs,
                border: Border.all(color: NotionColors.accentGreen.withAlpha(80), width: 0.8),
              ),
              child: Text(
                'P',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: NotionColors.tagGreenText,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Nội dung Sinh viên
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: NotionTypography.bodySm(
                            fontWeight: FontWeight.w600,
                            color: NotionColors.ink,
                          ),
                        ),
                      ),
                      if (displayRoll.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: NotionColors.canvasSoft,
                            borderRadius: NotionRounded.xs,
                            border: Border.all(color: NotionColors.hairline, width: 0.6),
                          ),
                          child: Text(
                            displayRoll,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: NotionColors.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Điểm danh thành công',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: NotionColors.tagGreenText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '• ${_formatTime(item.timestamp)}',
                        style: NotionTypography.caption(color: NotionColors.inkFaint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),

            // Nút Đóng
            InkWell(
              onTap: onDismiss,
              borderRadius: NotionRounded.xs,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: NotionColors.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
