import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:permission_handler/permission_handler.dart';

import 'download_manager.dart';

const String _downloadChannelId = 'com.jhelum.gyawun.downloads';
const String _downloadChannelName = 'Downloads';
const int _notificationId = 9001;
const int _completeNotificationId = 9002;

/// Top-level callback required by flutter_local_notifications for background actions.
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == 'CANCEL_DOWNLOAD' && response.payload != null) {
    try {
      GetIt.I<DownloadManager>().cancelDownload(response.payload!);
    } catch (_) {}
  }
}

class DownloadNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Timer? _updateTimer;
  DownloadManager? _downloadManager;
  bool _isInitialized = false;
  int _lastActiveCount = 0;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );

    // Request notification permission on Android 13+
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    _isInitialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'CANCEL_DOWNLOAD' && response.payload != null) {
      _downloadManager?.cancelDownload(response.payload!);
    }
  }

  void attach(DownloadManager dm) {
    if (!_isInitialized) return;
    _downloadManager = dm;

    // Listen to queue changes to start/stop the update timer
    dm.downloadQueue.addListener(_onQueueChanged);
    dm.downloads.addListener(_onQueueChanged);

    // Check initial state
    _onQueueChanged();
  }

  void _onQueueChanged() {
    final dm = _downloadManager;
    if (dm == null) return;

    final hasActive = dm.activeDownloadIds.isNotEmpty ||
        dm.downloadQueue.value.isNotEmpty;

    if (hasActive && _updateTimer == null) {
      _startUpdating();
    } else if (!hasActive && _updateTimer != null) {
      _stopUpdating();
      // Show completion notification if we had active downloads before
      if (_lastActiveCount > 0) {
        _showCompletionNotification();
      }
      _lastActiveCount = 0;
    }
  }

  void _startUpdating() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 750),
      (_) => _updateNotification(),
    );
    // Show immediately
    _updateNotification();
  }

  void _stopUpdating() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _plugin.cancel(_notificationId);
  }

  void _updateNotification() {
    final dm = _downloadManager;
    if (dm == null) return;

    final activeIds = dm.activeDownloadIds;
    final queuedCount = dm.downloadQueue.value.length;
    final totalCount = activeIds.length + queuedCount;

    if (activeIds.isEmpty && queuedCount == 0) {
      _stopUpdating();
      if (_lastActiveCount > 0) {
        _showCompletionNotification();
      }
      _lastActiveCount = 0;
      return;
    }

    _lastActiveCount = totalCount;

    // Get first active download's info
    String title = 'Downloading...';
    int progress = 0;
    String? firstVideoId;

    if (activeIds.isNotEmpty) {
      firstVideoId = activeIds.first;
      final songMeta = dm.getActiveSongMetadata(firstVideoId);
      final songTitle = songMeta?['title'] as String? ?? 'Unknown';
      title = songTitle;

      final progressNotifier = dm.activeDownloadProgress[firstVideoId];
      if (progressNotifier != null) {
        progress = (progressNotifier.value * 100).round().clamp(0, 100);
      }
    }

    // Build body text
    final completedCount = totalCount > 0 ? 1 : 0;
    final body = totalCount > 1
        ? 'Downloading $completedCount of $totalCount songs'
        : 'Downloading...';

    final androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: 'Shows download progress for songs',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      playSound: false,
      enableVibration: false,
      onlyAlertOnce: true,
      actions: firstVideoId != null
          ? [
              const AndroidNotificationAction(
                'CANCEL_DOWNLOAD',
                'Cancel',
                showsUserInterface: false,
                cancelNotification: false,
              ),
            ]
          : null,
    );

    _plugin.show(
      _notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: firstVideoId,
    );
  }

  Future<void> _showCompletionNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: 'Shows download progress for songs',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      playSound: false,
      enableVibration: false,
      timeoutAfter: 5000,
    );

    await _plugin.show(
      _completeNotificationId,
      'Downloads complete',
      'All songs have been downloaded',
      const NotificationDetails(android: androidDetails),
    );
  }

  void dispose() {
    _updateTimer?.cancel();
    _downloadManager?.downloadQueue.removeListener(_onQueueChanged);
    _downloadManager?.downloads.removeListener(_onQueueChanged);
    _plugin.cancel(_notificationId);
  }
}
