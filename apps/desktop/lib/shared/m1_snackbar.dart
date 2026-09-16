import 'package:flutter/material.dart';

/// Consistent M1 feedback: notices remain readable, but the lecturer can
/// dismiss them immediately without waiting for the timeout.
class M1SnackBar {
  const M1SnackBar._();

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: isError ? 8 : 5),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        content: Text(message),
        action: SnackBarAction(
          label: '✕',
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }
}
