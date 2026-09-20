import 'dart:async';

import 'package:flutter/material.dart';

enum M1NoticeType { success, warning, error }

/// Consistent M1 feedback with a ten-second timeout and an immediate close
/// action for lecturers who have already read the message.
class M1SnackBar {
  const M1SnackBar._();

  static const _displayDuration = Duration(seconds: 5);
  static Timer? _accessibleDismissTimer;

  static void show(
    BuildContext context,
    String message, {
    M1NoticeType type = M1NoticeType.success,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final (backgroundColor, icon) = switch (type) {
      M1NoticeType.success => (Colors.green.shade700, Icons.check_circle),
      M1NoticeType.warning => (Colors.amber.shade800, Icons.warning_amber),
      M1NoticeType.error => (Colors.red.shade700, Icons.error),
    };
    _accessibleDismissTimer?.cancel();
    _accessibleDismissTimer = null;
    messenger.hideCurrentSnackBar();

    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width > 420;

    final controller = messenger.showSnackBar(
      SnackBar(
        duration: _displayDuration,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          left: isCompact ? size.width - 360 : 16,
          right: 16,
          bottom: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Đóng thông báo',
              color: Colors.white,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: messenger.hideCurrentSnackBar,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );

    if (MediaQuery.accessibleNavigationOf(context)) {
      final timer = Timer(_displayDuration, controller.close);
      _accessibleDismissTimer = timer;
      controller.closed.whenComplete(() {
        timer.cancel();
        if (identical(_accessibleDismissTimer, timer)) {
          _accessibleDismissTimer = null;
        }
      });
    }
  }
}
