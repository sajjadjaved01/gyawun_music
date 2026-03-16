import 'package:flutter/foundation.dart';

/// Simple structured logger that replaces raw debugPrint calls.
class AppLogger {
  static void info(String message, {String? tag}) {
    _log('INFO', message, tag: tag);
  }

  static void warning(String message, {String? tag}) {
    _log('WARN', message, tag: tag);
  }

  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('ERROR', message, tag: tag);
    if (error != null) {
      debugPrint('  Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('  StackTrace: $stackTrace');
    }
  }

  static void _log(String level, String message, {String? tag}) {
    final prefix = tag != null ? '[$level][$tag]' : '[$level]';
    debugPrint('$prefix $message');
  }
}
