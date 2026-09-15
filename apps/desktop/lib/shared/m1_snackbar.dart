import 'package:flutter/material.dart';

/// Consistent M1 feedback: notices remain readable, but the lecturer can
/// dismiss them immediately without waiting for the timeout.
class M1SnackBar {
  const M1SnackBar._();

  static void show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 30),
        content: Text(message),
        action: SnackBarAction(
          label: '✕',
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }
}
