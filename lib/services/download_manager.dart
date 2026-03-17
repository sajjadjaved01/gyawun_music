import 'dart:collection';
import 'package:collection/collection.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:yt_music/ytmusic.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';
import 'file_storage.dart';
import 'settings_manager.dart';
import 'stream_client.dart';

Box _box = Hive.box('DOWNLOADS');
YoutubeExplode ytExplode = YoutubeExplode();

class DownloadManager {
  Client client = Client();
  ValueNotifier<List<Map>> downloads = ValueNotifier([]);
  ValueNotifier<Map<String, Map>> downloadsByPlaylist = ValueNotifier({});
  ValueNotifier<List<Map>> downloadQueue = ValueNotifier([]);
  final Map<String, ValueNotifier<double>> _activeDownloadProgress = {};
  final Map<String, AudioStreamClient> _activeStreamClients = {};
  static const String songsPlaylistId = 'songs';
  static const int maxConcurrentDownloads = AppConstants.maxConcurrentDownloads;
  final Queue<String> _activeDownloads = Queue<String>();
  final Queue<Map> _downloadQueue = Queue<Map>();
  bool _queueProcessing = false;

  DownloadManager() {
    _refreshData();
    _cleanupDownloads();
    _box.listenable().addListener(() {
      _refreshData();
    });
  }

  void _cleanupDownloads() async {
    final activeIds = _activeDownloads.toSet();
    final queuedIds = _downloadQueue.map((e) => e['videoId']).toSet();
    for (Map song in downloads.value) {
      final id = song['videoId'];
      final status = song['status'];
      final isInvalidDownloading =
          status == 'DOWNLOADING' && !activeIds.contains(id);
      final isInvalidQueued = status == 'QUEUED' && !queuedIds.contains(id);
      if (isInvalidDownloading || isInvalidQueued) {
        AppLogger.warning("Cleaning up interrupted download: ${song['title']}", tag: 'DownloadManager');
        await _updateSongMetadata(id, {'status': 'FAILED'});
      }
    }
  }

  Future<void> _refreshData() async {
    // -----------------------------
    // 0) LOAD DOWNLOADS FROM HIVE
    // -----------------------------
    downloads.value = _box.values.toList().cast<Map>();

    // -----------------------------
    // 1) MIGRATE OLD DOWNLOADS → SONGS
    // -----------------------------
    bool needsSave = false;

    for (final song in downloads.value) {
      if (song["playlists"] == null || song["playlists"] is! Map) {
        song["playlists"] = {
          songsPlaylistId: {
            "id": songsPlaylistId,
            "title": "Songs",
            "timestamp":
                song["downloadedAt"] ??
                song["timestamp"] ??
                DateTime.now().millisecondsSinceEpoch,
          },
        };
        needsSave = true;
      }
    }

    if (needsSave) {
      await _box.clear();
      await _box.addAll(downloads.value);
    }

    // -----------------------------
    // 2) PURGE DELETED DOWNLOADS
    // -----------------------------
    bool removedDeleted = false;

    downloads.value.removeWhere((song) {
      if (song["status"] == "DELETED") {
        removedDeleted = true;
        return true;
      }
      return false;
    });

    if (removedDeleted) {
      await _box.clear();
      await _box.addAll(downloads.value);
    }

    // -----------------------------
    // 3) BUILD PLAYLIST MAP
    // -----------------------------
    final Map<String, Map<String, dynamic>> playlists = {};

    for (final song in downloads.value) {
      final Map songPlaylists = Map.from(song["playlists"] ?? {});

      for (final entry in songPlaylists.entries) {
        final String id = entry.key;
        final value = entry.value;

        if (value is! Map) continue;

        final String title = value["title"] ?? "Unknown";

        playlists
            .putIfAbsent(
              id,
              () => {
                "id": id,
                "title": title,
                "type": id == songsPlaylistId ? "SONGS" : "ALBUM",
                "songs": <Map<String, dynamic>>[],
              },
            )["songs"]
            .add(Map<String, dynamic>.from(song));

        // ALBUM → PLAYLIST upgrade logic (unchanged, but safe)
        if (playlists[id]!["type"] == "ALBUM" &&
            playlists[id]!["title"] != song["album"]?["name"]) {
          playlists[id]!["type"] = "PLAYLIST";
        }
      }
    }

    // -----------------------------
    // 4) SORT SONGS INSIDE PLAYLISTS
    // -----------------------------
    for (final playlist in playlists.values) {
      final String playlistId = playlist["id"];

      (playlist["songs"] as List).sort((a, b) {
        final aTs = a["playlists"]?[playlistId]?["timestamp"] ?? 0;
        final bTs = b["playlists"]?[playlistId]?["timestamp"] ?? 0;
        return aTs.compareTo(bTs);
      });
    }

    // -----------------------------
    // 5) UPDATE STATE IF CHANGED
    // -----------------------------
    if (!const DeepCollectionEquality().equals(
      downloadsByPlaylist.value,
      playlists,
    )) {
      downloadsByPlaylist.value = playlists;
    }
  }

  List<Map> getDownloadQueue() {
    return _downloadQueue.toList();
  }

  void _notifyQueueChange() {
    downloadQueue.value = List<Map>.from(_downloadQueue);
  }

  Future<void> cancelDownload(String videoId) async {
    // Remove from queue if queued
    _downloadQueue.removeWhere((song) => song['videoId'] == videoId);
    _notifyQueueChange();

    // Cancel active download by closing its stream client
    if (_activeStreamClients.containsKey(videoId)) {
      _activeStreamClients[videoId]!.close();
      _activeStreamClients.remove(videoId);
    }

    _activeDownloads.remove(videoId);
    _stopTrackingProgress(videoId);
    await _updateSongMetadata(videoId, {'status': 'DELETED'});
    _processQueue();
  }

  Set<String> get activeDownloadIds => Set.unmodifiable(_activeDownloads);

  Map<String, ValueNotifier<double>> get activeDownloadProgress =>
      Map.unmodifiable(_activeDownloadProgress);

  /// Returns the song metadata for a currently active download.
  Map? getActiveSongMetadata(String videoId) => _box.get(videoId);

  ValueNotifier<double>? getProgressNotifier(String videoId) {
    return _activeDownloadProgress[videoId];
  }

  void _startTrackingProgress(String videoId) {
    _activeDownloadProgress[videoId]?.dispose();
    _activeDownloadProgress[videoId] = ValueNotifier(0.0);
  }

  void _updateTrackingProgress(String videoId, double value) {
    _activeDownloadProgress[videoId]?.value = value;
  }

  void _stopTrackingProgress(String videoId) {
    if (_activeDownloadProgress.containsKey(videoId)) {
      _activeDownloadProgress[videoId]!.dispose();
      _activeDownloadProgress.remove(videoId);
    }
  }

  Future<void> restoreDownloads({List? songs}) async {
    final songsToRestore = songs ?? downloads.value;
    for (var song in songsToRestore) {
      if (_box.get(song['videoId']) != null) {
        final status = song['status'];
        final path = song['path'];
        final isFileMissing =
            status == 'DOWNLOADED' &&
            (path == null || !(await File(path).exists()));
        final isDeleted = status == 'DELETED';
        final isFailed = status == 'FAILED';
        if (isDeleted || isFailed || isFileMissing) {
          // Preserve the original download type (audio vs video) when restoring.
          final bool wasVideo = song['isVideo'] == true || song['downloadAsVideo'] == true;
          downloadSong(song, asVideo: wasVideo);
        }
      }
    }
  }

  Future<void> downloadSong(Map songToDownaload, {bool? asVideo}) async {
    final bool isVideo = asVideo ?? (GetIt.I<SettingsManager>().downloadType == DownloadType.video);
    final Map song = {
      ...songToDownaload,
      'downloadAsVideo': isVideo,
      'playlists':
          songToDownaload['playlists'] ??
          {
            songsPlaylistId: {
              'title': 'Songs',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          },
    };

    final Map? existing = _box.get(song['videoId']);
    if (existing != null) {
      if (_activeDownloads.contains(song['videoId'])) {
        await _updateSongMetadata(song['videoId'], {...song});
        return;
      } else {
        final String? path = existing['path'];
        if (path != null) {
          final file = File(path);
          final exists = await file.exists();
          if (exists) {
            await _updateSongMetadata(song['videoId'], {
              ...song,
              'status': 'DOWNLOADED',
            });
            return;
          }
        }
      }
    }

    if (_activeDownloads.length >= maxConcurrentDownloads) {
      if (!_downloadQueue.any((s) => s['videoId'] == song['videoId'])) {
        _downloadQueue.add(song);
        _notifyQueueChange();
        await _updateSongMetadata(song['videoId'], {...song, 'status': 'QUEUED'});
      }
    } else {
      _activeDownloads.add(song['videoId']);
      await _downloadSong(song);
      _activeDownloads.remove(song['videoId']);
    }

    _processQueue();
  }

  Future<void> _downloadSong(Map song) async {
    try {
      await _updateSongMetadata(song['videoId'], {
        ...song,
        'status': 'DOWNLOADING',
      });
      _startTrackingProgress(song['videoId']);

      if (!(await FileStorage.requestPermissions())) {
        throw Exception('Storage permissions not granted.');
      }

      final bool isVideo = song['downloadAsVideo'] == true;

      if (isVideo) {
        await _downloadVideoSong(song);
      } else {
        await _downloadAudioSong(song);
      }
    } catch (e, stackTrace) {
      AppLogger.error("Download failed for '${song['title']}'", tag: 'DownloadManager', error: e, stackTrace: stackTrace);
      await _updateSongMetadata(song['videoId'], {'status': 'FAILED'});
    } finally {
      _stopTrackingProgress(song['videoId']);
    }
  }

  Future<void> _downloadAudioSong(Map song) async {
    AudioOnlyStreamInfo audioSource = await _getSongInfo(
      song['videoId'],
      quality: GetIt.I<SettingsManager>().downloadQuality.name.toLowerCase(),
    );

    int total = audioSource.size.totalBytes;
    BytesBuilder received = BytesBuilder();

    final streamClient = AudioStreamClient();
    _activeStreamClients[song['videoId']] = streamClient;

    Stream<List<int>> stream = streamClient.getAudioStream(
      audioSource,
      start: 0,
      end: total,
    );

    await for (var data in stream) {
      received.add(data);
      _updateTrackingProgress(song['videoId'], received.length / total);
    }
    _activeStreamClients.remove(song['videoId']);
    File? file = await GetIt.I<FileStorage>().saveMusic(
      received.takeBytes(),
      song,
    );
    if (file != null) {
      await _updateSongMetadata(song['videoId'], {
        'status': 'DOWNLOADED',
        'path': file.path,
        'isVideo': false,
      });
    } else {
      throw Exception("File saving failed");
    }
  }

  Future<void> _downloadVideoSong(Map song) async {
    final targetHeight = GetIt.I<SettingsManager>().videoQuality.height;
    final videoSource = await _getMuxedVideoStreamInfo(
      song['videoId'],
      targetHeight: targetHeight,
    );

    int total = videoSource.size.totalBytes;
    BytesBuilder received = BytesBuilder();

    final streamClient = AudioStreamClient();
    _activeStreamClients[song['videoId']] = streamClient;

    Stream<List<int>> stream = streamClient.getAudioStream(
      videoSource,
      start: 0,
      end: total,
    );

    await for (var data in stream) {
      received.add(data);
      _updateTrackingProgress(song['videoId'], received.length / total);
    }
    _activeStreamClients.remove(song['videoId']);
    File? file = await GetIt.I<FileStorage>().saveVideo(
      received.takeBytes(),
      song,
    );
    if (file != null) {
      await _updateSongMetadata(song['videoId'], {
        'status': 'DOWNLOADED',
        'path': file.path,
        'isVideo': true,
      });
    } else {
      throw Exception("Video file saving failed");
    }
  }

  Future<void> _updateSongMetadata(String key, Map newMetadata) async {
    Map? song = _box.get(key);
    if (song != null) {
      if (newMetadata.containsKey('playlists')) {
        Map<String, dynamic> mergedPlaylists = {};
        if (song['playlists'] != null) {
          (song['playlists'] as Map).forEach((k, v) {
            mergedPlaylists[k] = Map<String, dynamic>.from(v);
          });
        }
        (newMetadata['playlists'] as Map).forEach((k, v) {
          mergedPlaylists[k] = Map<String, dynamic>.from(v);
        });
        song['playlists'] = mergedPlaylists;
        newMetadata.remove('playlists');
      }
      await _box.put(key, {...song, ...newMetadata});
    } else {
      await _box.put(key, newMetadata);
    }
  }

  /// Drains the pending queue into available download slots.
  /// Only one concurrent invocation runs at a time.
  Future<void> _processQueue() async {
    if (_queueProcessing) return;
    _queueProcessing = true;
    try {
      while (_downloadQueue.isNotEmpty &&
          _activeDownloads.length < maxConcurrentDownloads) {
        final next = _downloadQueue.removeFirst();
        _notifyQueueChange();
        _activeDownloads.add(next['videoId'] as String);
        _runWorker(next);
      }
    } finally {
      _queueProcessing = false;
    }
  }

  Future<void> _runWorker(Map song) async {
    await _downloadSong(song);
    _activeDownloads.remove(song['videoId']);
    _processQueue();
  }

  Future<String> deleteSong({
    required String key,
    String playlistId = songsPlaylistId,
    String? path,
  }) async {
    Map? song = _box.get(key);
    if (song != null && song['playlists'].keys.contains(playlistId)) {
      song['playlists'].remove(playlistId);
      if (song['playlists'].isNotEmpty) {
        await _box.put(key, song);
      } else {
        await _box.delete(key);
        if (path != null && await File(path).exists()) {
          await File(path).delete();
        }
      }
    }
    return 'Song deleted successfully.';
  }

  Future<void> updateStatus(String key, String status) async {
    Map? song = _box.get(key);
    if (song != null) {
      song['status'] = status;
      await _box.put(key, song);
    }
  }

  Future<void> downloadPlaylist(Map playlist) async {
    List songs = playlist['isPredefined'] == false
        ? playlist['songs']
        : playlist['type'] == 'ARTIST'
        ? await GetIt.I<YTMusic>().getNextSongList(
            playlistId: playlist['playlistId'],
          )
        : await GetIt.I<YTMusic>().getPlaylistSongs(playlist['playlistId']);
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    for (Map song in songs) {
      downloadSong({
        ...song,
        'playlists': {
          playlist['playlistId']: {
            'title': playlist['title'],
            'timestamp': timestamp++,
          },
        },
      }); // Queue each song download
    }
  }

  Future<AudioOnlyStreamInfo> _getSongInfo(
    String videoId, {
    String quality = 'high',
  }) async {
    try {
      StreamManifest manifest = await ytExplode.videos.streamsClient
          .getManifest(
            videoId,
            requireWatchPage: true,
            ytClients: [YoutubeApiClient.androidVr],
          );
      List<AudioOnlyStreamInfo> streamInfos = manifest.audioOnly
          .where((a) => a.container == StreamContainer.mp4)
          .sortByBitrate()
          .reversed
          .toList();
      return quality == 'low' ? streamInfos.first : streamInfos.last;
    } catch (e) {
      rethrow;
    }
  }

  Future<MuxedStreamInfo> _getMuxedVideoStreamInfo(
    String videoId, {
    int targetHeight = 480,
  }) async {
    StreamManifest manifest = await ytExplode.videos.streamsClient
        .getManifest(
          videoId,
          requireWatchPage: true,
          ytClients: [YoutubeApiClient.androidVr],
        );

    final muxed = manifest.muxed.toList();
    if (muxed.isEmpty) {
      throw Exception('No muxed video streams available for $videoId');
    }

    // Sort by video height ascending and pick closest to targetHeight.
    muxed.sort((a, b) => a.videoResolution.height.compareTo(b.videoResolution.height));

    MuxedStreamInfo selected = muxed.first;
    for (final stream in muxed) {
      if (stream.videoResolution.height <= targetHeight) {
        selected = stream;
      } else {
        break;
      }
    }
    return selected;
  }

  /// Returns the estimated size in bytes for a video download at the given quality,
  /// or null if unavailable.
  Future<int?> getVideoStreamSize(String videoId, int targetHeight) async {
    try {
      final stream = await _getMuxedVideoStreamInfo(videoId, targetHeight: targetHeight);
      return stream.size.totalBytes;
    } catch (_) {
      return null;
    }
  }

  /// Returns the estimated size in bytes for an audio download,
  /// or null if unavailable.
  Future<int?> getAudioStreamSize(String videoId) async {
    try {
      final stream = await _getSongInfo(
        videoId,
        quality: GetIt.I<SettingsManager>().downloadQuality.name.toLowerCase(),
      );
      return stream.size.totalBytes;
    } catch (_) {
      return null;
    }
  }
}
