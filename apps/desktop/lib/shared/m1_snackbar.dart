import 'dart:async';

import 'package:flutter/material.dart';

enum M1NoticeType { success, warning, error }

/// Consistent M1 feedback with a ten-second timeout and an immediate close
/// action for lecturers who have already read the message.
class M1SnackBar {
  const M1SnackBar._();

  static const _displayDuration = Duration(seconds: 10);
  static Timer? _dismissTimer;

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
    _dismissTimer?.cancel();
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
          ],
        ),
        action: SnackBarAction(
          label: '✕',
          textColor: Colors.white,
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );

    // A SnackBar with an action is intentionally kept on screen indefinitely
    // when accessible navigation is enabled. Enforce the product's timeout on
    // desktop while closing this controller only, so a newer notice is safe.
    final timer = Timer(_displayDuration, controller.close);
    _dismissTimer = timer;
    controller.closed.whenComplete(() {
      timer.cancel();
      if (identical(_dismissTimer, timer)) {
        _dismissTimer = null;
      }
    });
  }
}
