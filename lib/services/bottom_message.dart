import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

class BottomMessage {
  static void showText(
    BuildContext context,
    String text, {
    Duration duration = AppConstants.snackBarDuration,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
