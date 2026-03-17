import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  // The flutter_wear_os_connectivity package emits dynamic message events from
  // its messageReceived() stream.  The object has .path and .data fields
  // (where .data is a Uint8List / List<int>).  We keep the parameter typed as
  // dynamic so that minor version differences in the package don't cause
  // compile errors.
  Future<void> _handleMessage(dynamic event) async {
    try {
      final String path = (event.path ?? event.data?.path ?? '') as String;
      final List<int> rawBytes =
          (event.data is List ? event.data as List<int> : event.data?.data ?? []) as List<int>;
      final String payload = utf8.decode(rawBytes);

      // The source node id may be on the event directly or nested under .data.
      final String? sourceNodeId =
          (event.sourceNodeId ?? event.data?.sourceNodeId) as String?;

      switch (path) {
        case SyncConstants.playbackCommand:
          await _handlePlaybackCommand(payload);

        case SyncConstants.librarySync:
          await _handleLibrarySyncRequest(sourceNodeId);

        case SyncConstants.downloadRequest:
          await _handleDownloadRequest(payload, sourceNodeId);

        case SyncConstants.searchQuery:
          await _handleSearchRequest(payload, sourceNodeId);

        default:
          debugPrint('[WearSyncService] Unknown message path: $path');
      }
    } catch (e) {
      debugPrint('[WearSyncService] Error dispatching message: $e');
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
          debugPrint('[WearSyncService] Unknown playback command: $command');
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
            // Strip the full songs list; the watch requests song details separately.
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

      // Use DataClient (persistent) rather than a transient MessageClient call
      // so the watch can read the data even after brief disconnections.
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

  /// Handles a request from the watch for a downloaded audio file.
  ///
  /// Large files are broken into 100 KB DataClient chunks because the Wearable
  /// Message API has a hard limit of ~100 KB per message.  Each chunk is stored
  /// at a distinct DataClient path keyed by [videoId] and chunk index.  The
  /// watch reassembles the chunks in order.
  ///
  /// NOTE: If the underlying [flutter_wear_os_connectivity] version exposes a
  /// dedicated ChannelClient API (e.g. `openChannel` / `getOutputStream`), that
  /// is the preferred mechanism and should replace the chunked DataClient
  /// approach below.  The DataClient path is used as a fallback because it
  /// works without a persistent low-latency channel.
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

      // Read file and send in 100 KB DataClient chunks.
      const int chunkSize = 100 * 1024;
      final Uint8List bytes = await file.readAsBytes();
      final int totalChunks = (bytes.length / chunkSize).ceil();
      int chunkIndex = 0;
      int offset = 0;

      while (offset < bytes.length) {
        final int end = (offset + chunkSize).clamp(0, bytes.length);
        final Uint8List chunk = bytes.sublist(offset, end);

        await _wearOs.syncData(
          '/transfer/$videoId/chunk_$chunkIndex',
          data: {
            'videoId': videoId,
            'chunkIndex': chunkIndex,
            'totalChunks': totalChunks,
            'bytes': chunk,
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

      final dynamic results = await GetIt.I<YTMusic>().search(query);

      // Strip results to essential metadata to stay within message size limits.
      final List<Map<String, dynamic>> compact =
          ((results as List?) ?? []).whereType<Map>().map((item) {
        final m = Map<String, dynamic>.from(item);
        return <String, dynamic>{
          'videoId': m['videoId'],
          'title': m['title'],
          'artists': m['artists'],
          'thumbnails': m['thumbnails'],
          'type': m['type'],
        };
      }).take(20).toList();

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
