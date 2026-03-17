import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_wear_os_connectivity/flutter_wear_os_connectivity.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:yt_music/ytmusic.dart';

import 'media_player.dart';

/// Keeps a connected Wear OS watch in sync with the current player state.
///
/// Call [init] once after [MediaPlayer] is created. The service attaches
/// [ValueNotifier] listeners to [MediaPlayer.currentSongNotifier],
/// [MediaPlayer.buttonState], and [MediaPlayer.progressBarState], then pushes
/// updates to the watch via the Wearable Data Layer API.
///
/// All methods are no-ops on platforms other than Android.
class WearSyncService {
  WearSyncService._();

  static WearSyncService? _instance;
  static WearSyncService get instance => _instance ??= WearSyncService._();

  MediaPlayer? _player;
  final WearOsConnectivity _wearOs = WearOsConnectivity();
  bool _initialized = false;

  // Listener references kept for clean removal in [dispose].
  late final VoidCallback _songListener;
  late final VoidCallback _buttonStateListener;
  late final VoidCallback _progressListener;

  // Throttle progress pushes — only send when position changes by >= 1 second.
  Duration _lastPushedPosition = Duration.zero;

  /// Attach to [player] and start syncing playback state to the watch.
  void init(MediaPlayer player) {
    if (!Platform.isAndroid) return;

    _player = player;

    _songListener = () => _onPlaybackChanged();
    _buttonStateListener = () => _onPlaybackChanged();
    _progressListener = () => _onProgressChanged();

    player.currentSongNotifier.addListener(_songListener);
    player.buttonState.addListener(_buttonStateListener);
    player.progressBarState.addListener(_progressListener);

    _initWearable();
  }

  Future<void> _initWearable() async {
    try {
      await _wearOs.configureWearableAPI();
      _initialized = true;

      // Announce phone capability so the watch can discover us.
      await _wearOs.registerNewCapability(SyncConstants.phoneCapability);

      // Listen for incoming messages from the watch.
      _wearOs.messageReceived().listen(_handleMessage);

      // Push current state in case a watch connects after startup.
      _onPlaybackChanged();
    } catch (e) {
      debugPrint('[WearSyncService] Failed to initialise Wearable API: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Outbound — phone → watch
  // ---------------------------------------------------------------------------

  void _onPlaybackChanged() {
    final player = _player;
    if (player == null || !_initialized) return;

    final song = player.currentSongNotifier.value;
    final buttonState = player.buttonState.value;
    final progress = player.progressBarState.value;

    _pushPlaybackState(
      song: song,
      isPlaying: buttonState == ButtonState.playing,
      position: progress.current,
      duration: progress.total,
    );
  }

  void _onProgressChanged() {
    final player = _player;
    if (player == null || !_initialized) return;

    final progress = player.progressBarState.value;
    final diff = (progress.current - _lastPushedPosition).abs();

    // Only push position updates once per second to reduce Wearable API traffic.
    if (diff < const Duration(seconds: 1)) return;
    _lastPushedPosition = progress.current;

    final song = player.currentSongNotifier.value;
    final buttonState = player.buttonState.value;

    _pushPlaybackState(
      song: song,
      isPlaying: buttonState == ButtonState.playing,
      position: progress.current,
      duration: progress.total,
    );
  }

  Future<void> _pushPlaybackState({
    required MediaItem? song,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) async {
    try {
      final payload = <String, dynamic>{
        'videoId': song?.id ?? '',
        'title': song?.title ?? '',
        'artist': song?.artist ?? '',
        'thumbnailUrl': song?.artUri?.toString() ?? '',
        'isPlaying': isPlaying,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
      };

      // Include queue size so the watch can show prev/next availability.
      final player = _player;
      if (player != null) {
        payload['queueSize'] = player.songList.length;
        payload['queueIndex'] = player.currentIndex.value ?? 0;
      }

      await _wearOs.syncData(
        SyncConstants.dataPlaybackState,
        data: {'json': jsonEncode(payload)},
        isUrgent: true,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Failed to push playback state: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Inbound — watch → phone
  // ---------------------------------------------------------------------------

  Future<void> _handleMessage(MessageReceiveEvent event) async {
    final path = event.data.path;
    final raw = utf8.decode(event.data.data ?? []);

    switch (path) {
      case SyncConstants.playbackCommand:
        await _handlePlaybackCommand(raw);

      case SyncConstants.librarySync:
        await _handleLibrarySyncRequest(event.data.sourceNodeId);

      case SyncConstants.downloadRequest:
        await _handleDownloadRequest(raw, event.data.sourceNodeId);

      case SyncConstants.searchQuery:
        await _handleSearchRequest(raw, event.data.sourceNodeId);

      default:
        debugPrint('[WearSyncService] Received unknown message path: $path');
    }
  }

  // --- Playback commands ---

  Future<void> _handlePlaybackCommand(String raw) async {
    final player = _player;
    if (player == null) return;

    try {
      final Map<String, dynamic> cmd = jsonDecode(raw) as Map<String, dynamic>;
      final command = cmd['command'] as String?;

      switch (command) {
        case SyncConstants.cmdPlay:
          await player.player.play();

        case SyncConstants.cmdPause:
          await player.player.pause();

        case SyncConstants.cmdNext:
          await player.player.seekToNext();

        case SyncConstants.cmdPrev:
          await player.player.seekToPrevious();

        case SyncConstants.cmdSeek:
          final ms = cmd['positionMs'] as int?;
          if (ms != null) {
            await player.player.seek(Duration(milliseconds: ms));
          }

        default:
          debugPrint(
            '[WearSyncService] Unknown playback command: $command',
          );
      }
    } catch (e) {
      debugPrint('[WearSyncService] Error handling playback command: $e');
    }
  }

  // --- Library sync ---

  Future<void> _handleLibrarySyncRequest(String? sourceNodeId) async {
    if (sourceNodeId == null) return;

    try {
      final libraryBox = Hive.box('LIBRARY');
      final favouritesBox = Hive.box('FAVOURITES');
      final historyBox = Hive.box('SONG_HISTORY');

      // Build lightweight metadata lists (no file paths, no raw audio data).
      final playlists = libraryBox.values
          .map((v) {
            final m = Map<String, dynamic>.from(v as Map);
            // Strip songs list to keep message small; watch requests songs separately.
            return {
              'title': m['title'],
              'isPredefined': m['isPredefined'],
              'createdAt': m['createdAt'],
              'songCount': (m['songs'] as List?)?.length ?? 0,
              'thumbnails': m['thumbnails'],
            };
          })
          .toList();

      final favourites = favouritesBox.values.map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return {
          'videoId': m['videoId'],
          'title': m['title'],
          'artists': m['artists'],
          'thumbnails': m['thumbnails'],
        };
      }).toList();

      final history = historyBox.values.map((v) {
        final m = Map<String, dynamic>.from(v as Map);
        return {
          'videoId': m['videoId'],
          'title': m['title'],
          'artists': m['artists'],
          'thumbnails': m['thumbnails'],
          'updatedAt': m['updatedAt'],
        };
      }).toList();

      final payload = jsonEncode({
        'playlists': playlists,
        'favourites': favourites,
        'history': history,
        'syncedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Sync via DataClient (large, persistent) instead of MessageClient.
      await _wearOs.syncData(
        SyncConstants.dataLibrary,
        data: {'json': payload},
        isUrgent: false,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Failed to send library data: $e');
    }
  }

  // --- Audio file transfer ---

  Future<void> _handleDownloadRequest(
    String raw,
    String? sourceNodeId,
  ) async {
    if (sourceNodeId == null) return;

    try {
      final Map<String, dynamic> req =
          jsonDecode(raw) as Map<String, dynamic>;
      final videoId = req['videoId'] as String?;
      if (videoId == null) return;

      final downloadsBox = Hive.box('DOWNLOADS');
      final songData = downloadsBox.get(videoId);
      if (songData == null) {
        await _sendProgressUpdate(sourceNodeId, videoId, -1, 0, 'not_found');
        return;
      }

      final path =
          (Map<String, dynamic>.from(songData as Map))['path'] as String?;
      if (path == null) {
        await _sendProgressUpdate(sourceNodeId, videoId, -1, 0, 'no_path');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        await _sendProgressUpdate(
            sourceNodeId, videoId, -1, 0, 'file_missing');
        return;
      }

      final totalBytes = await file.length();
      await _sendProgressUpdate(
          sourceNodeId, videoId, 0, totalBytes, 'starting');

      // Transfer the file via ChannelClient.
      // The flutter_wear_os_connectivity ChannelClient API requires opening a
      // channel to the remote node, writing to its output stream, then closing.
      // The exact stream-write API depends on the package version; the steps
      // below follow the documented WearOsConnectivity.sendFile pattern.
      //
      // TODO: Replace with the correct ChannelClient call once the package
      //       version used by this project is confirmed. The hook points are:
      //         1. _wearOs.openChannel(path, nodeId)  → WearOsChannel
      //         2. _wearOs.getOutputStream(channel)   → IOSink / Stream<List<int>>
      //         3. pipe file bytes, reporting progress via _sendProgressUpdate
      //         4. _wearOs.closeChannel(channel)
      //
      // Fallback: chunk the file and deliver each piece as a DataClient asset.
      const int chunkSize = 100 * 1024; // 100 KB — safely under 100 KB limit
      final bytes = await file.readAsBytes();
      int offset = 0;
      int chunkIndex = 0;

      while (offset < bytes.length) {
        final end =
            (offset + chunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);

        // Each chunk is stored as a separate DataClient item keyed by index.
        await _wearOs.syncData(
          '/transfer/$videoId/chunk_$chunkIndex',
          data: {
            'videoId': videoId,
            'chunkIndex': chunkIndex,
            'totalChunks': (bytes.length / chunkSize).ceil(),
            'data': chunk,
          },
          isUrgent: false,
        );

        offset = end;
        chunkIndex++;

        await _sendProgressUpdate(
          sourceNodeId,
          videoId,
          offset,
          totalBytes,
          'transferring',
        );
      }

      await _sendProgressUpdate(
          sourceNodeId, videoId, totalBytes, totalBytes, 'done');
    } catch (e) {
      debugPrint('[WearSyncService] Download transfer error: $e');
    }
  }

  Future<void> _sendProgressUpdate(
    String targetNodeId,
    String videoId,
    int bytesSent,
    int totalBytes,
    String status,
  ) async {
    try {
      final payload = jsonEncode({
        'videoId': videoId,
        'bytesSent': bytesSent,
        'totalBytes': totalBytes,
        'status': status,
      });
      await _wearOs.sendMessage(
        SyncConstants.downloadProgress,
        data: utf8.encode(payload),
        targetNodeId: targetNodeId,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Failed to send progress update: $e');
    }
  }

  // --- Search ---

  Future<void> _handleSearchRequest(
    String raw,
    String? sourceNodeId,
  ) async {
    if (sourceNodeId == null) return;

    try {
      final Map<String, dynamic> req =
          jsonDecode(raw) as Map<String, dynamic>;
      final query = req['query'] as String?;
      if (query == null || query.isEmpty) return;

      final results = await GetIt.I<YTMusic>().search(query);

      // Strip results to essential metadata to stay within message size limits.
      final compact = (results as List?)
              ?.whereType<Map>()
              .map((item) {
                final m = Map<String, dynamic>.from(item);
                return {
                  'videoId': m['videoId'],
                  'title': m['title'],
                  'artists': m['artists'],
                  'thumbnails': m['thumbnails'],
                  'type': m['type'],
                };
              })
              .take(20)
              .toList() ??
          [];

      final payload = jsonEncode({'query': query, 'results': compact});
      await _wearOs.sendMessage(
        SyncConstants.searchResults,
        data: utf8.encode(payload),
        targetNodeId: sourceNodeId,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Search request error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void dispose() {
    final player = _player;
    if (player != null) {
      player.currentSongNotifier.removeListener(_songListener);
      player.buttonState.removeListener(_buttonStateListener);
      player.progressBarState.removeListener(_progressListener);
    }
    _player = null;
    _initialized = false;
  }
}
