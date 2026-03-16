/// Application-wide constants extracted from inline magic numbers.
abstract final class AppConstants {
  // Download manager
  static const int maxConcurrentDownloads = 3;

  // HTTP stream client retry budget
  static const int httpRetryCount = 5;

  // Delay between retry attempts
  static const Duration retryDelay = Duration(milliseconds: 500);

  // MediaKit audio buffer size for Windows/Linux (8 MiB)
  static const int mediaKitBufferSize = 8 * 1024 * 1024;

  // Default snackbar display duration
  static const Duration snackBarDuration = Duration(milliseconds: 1500);

  // YouTube config fetch timeout on startup
  static const Duration ytConfigFetchTimeout = Duration(seconds: 10);

  // Stats reporting interval
  static const Duration statsReportInterval = Duration(seconds: 10);
}
