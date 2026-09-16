import 'dart:async';

import 'package:flutter/material.dart';

enum M1NoticeType { success, warning, error }

/// Consistent M1 feedback with a ten-second timeout and an immediate close
/// action for lecturers who have already read the message.
class M1SnackBar {
  const M1SnackBar._();

  static const _displayDuration = Duration(seconds: 10);
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
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: _displayDuration,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            IconButton(
              tooltip: 'Đóng thông báo',
              color: Colors.white,
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
