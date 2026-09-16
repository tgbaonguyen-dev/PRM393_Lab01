import 'package:flutter/material.dart';

enum M1NoticeType { success, warning, error }

/// Consistent M1 feedback with a ten-second timeout and an immediate close
/// action for lecturers who have already read the message.
class M1SnackBar {
  const M1SnackBar._();

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
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
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
  }
}
