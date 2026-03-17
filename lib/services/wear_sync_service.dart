import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:yt_music/ytmusic.dart';

import 'media_player.dart';
import 'wear_bridge.dart';

/// Keeps a connected Wear OS watch in sync with the current player state.
///
/// Call [init] once after [MediaPlayer] is created. The service attaches
/// [ValueNotifier] listeners to [MediaPlayer.currentSongNotifier],
/// [MediaPlayer.buttonState], and [MediaPlayer.progressBarState], then pushes
/// updates to the watch via [WearBridge].
///
/// All methods are no-ops on platforms other than Android.
class WearSyncService {
  WearSyncService._();

  static WearSyncService? _instance;
  static WearSyncService get instance => _instance ??= WearSyncService._();

  MediaPlayer? _player;
  final WearBridge _bridge = WearBridge.instance;
  bool _initialized = false;

  late final VoidCallback _songListener;
  late final VoidCallback _buttonStateListener;
  late final VoidCallback _progressListener;

  Duration _lastPushedPosition = Duration.zero;

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
      _initialized = true;

      // Listen for incoming messages/data from the watch.
      _bridge.events.listen(_handleEvent);

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

      final player = _player;
      if (player != null) {
        payload['queueSize'] = player.songList.length;
        payload['queueIndex'] = player.currentIndex.value ?? 0;
      }

      await _bridge.syncData(
        SyncConstants.dataPlaybackState,
        json: jsonEncode(payload),
        urgent: true,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Failed to push playback state: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Inbound — watch → phone
  // ---------------------------------------------------------------------------

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    try {
      final type = event['type'] as String?;
      final path = event['path'] as String? ?? '';
      final rawData = event['data'] as String? ?? '';
      final sourceNodeId = event['sourceNodeId'] as String?;

      if (type == 'message') {
        switch (path) {
          case SyncConstants.playbackCommand:
            await _handlePlaybackCommand(rawData);
          case SyncConstants.librarySync:
            await _handleLibrarySyncRequest(sourceNodeId);
          case SyncConstants.downloadRequest:
            await _handleDownloadRequest(rawData, sourceNodeId);
          case SyncConstants.searchQuery:
            await _handleSearchRequest(rawData, sourceNodeId);
          default:
            debugPrint('[WearSyncService] Unknown message path: $path');
        }
      }
    } catch (e) {
      debugPrint('[WearSyncService] Error dispatching event: $e');
    }
  }

  Future<void> _handlePlaybackCommand(String raw) async {
    final player = _player;
    if (player == null) return;

    try {
      final Map<String, dynamic> cmd =
          jsonDecode(raw) as Map<String, dynamic>;
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
          debugPrint('[WearSyncService] Unknown command: $command');
      }
    } catch (e) {
      debugPrint('[WearSyncService] Error handling playback command: $e');
    }
  }

  Future<void> _handleLibrarySyncRequest(String? sourceNodeId) async {
    if (sourceNodeId == null) return;

    try {
      final libraryBox = Hive.box('LIBRARY');
      final favouritesBox = Hive.box('FAVOURITES');
      final historyBox = Hive.box('SONG_HISTORY');

      final playlists = libraryBox.values
          .map((v) {
            final m = Map<String, dynamic>.from(v as Map);
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

      await _bridge.syncData(
        SyncConstants.dataLibrary,
        json: payload,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Failed to send library data: $e');
    }
  }

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

      const int chunkSize = 100 * 1024;
      final Uint8List bytes = await file.readAsBytes();
      final int totalChunks = (bytes.length / chunkSize).ceil();
      int chunkIndex = 0;
      int offset = 0;

      while (offset < bytes.length) {
        final int end = (offset + chunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);

        await _bridge.syncData(
          '/transfer/$videoId/chunk_$chunkIndex',
          json: jsonEncode({
            'videoId': videoId,
            'chunkIndex': chunkIndex,
            'totalChunks': totalChunks,
            'bytes': chunk.toList(),
          }),
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
      await _bridge.sendMessage(
        SyncConstants.downloadProgress,
        data: payload,
        targetNodeId: targetNodeId,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Failed to send progress update: $e');
    }
  }

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
      await _bridge.sendMessage(
        SyncConstants.searchResults,
        data: payload,
        targetNodeId: sourceNodeId,
      );
    } catch (e) {
      debugPrint('[WearSyncService] Search request error: $e');
    }
  }

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
