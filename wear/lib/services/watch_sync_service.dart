import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_wear_os_connectivity/flutter_wear_os_connectivity.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'watch_media_player.dart';

// ---------------------------------------------------------------------------
// WatchSyncService
//
// Bridges the Wear OS Data Layer API with the rest of the app:
//   - DataClient  : receives library / playback state from the phone
//   - MessageClient: sends playback commands and search queries to the phone
//   - ChannelClient: receives audio files pushed from the phone
// ---------------------------------------------------------------------------
class WatchSyncService extends ChangeNotifier {
  final FlutterWearOsConnectivity _connectivity = FlutterWearOsConnectivity();

  // Connection state
  bool _phoneConnected = false;
  bool get phoneConnected => _phoneConnected;

  // Library data received from phone
  List<PlaylistModel> _playlists = [];
  List<SongModel> _favourites = [];
  List<SongModel> _searchResults = [];

  List<PlaylistModel> get playlists => List.unmodifiable(_playlists);
  List<SongModel> get favourites => List.unmodifiable(_favourites);
  List<SongModel> get searchResults => List.unmodifiable(_searchResults);

  // Stream controller for search results so UI can react
  final StreamController<List<SongModel>> _searchResultsController =
      StreamController<List<SongModel>>.broadcast();
  Stream<List<SongModel>> get searchResultsStream =>
      _searchResultsController.stream;

  // Download progress: videoId -> 0.0..1.0
  final Map<String, double> _downloadProgress = {};
  Map<String, double> get downloadProgress =>
      Map.unmodifiable(_downloadProgress);

  StreamSubscription<WearOsMessage>? _messageSub;
  StreamSubscription<DataEvent>? _dataSub;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------
  Future<void> init() async {
    try {
      await _connectivity.configureWearableAPI();
      await _checkPhoneConnection();
      _listenToMessages();
      _listenToDataLayer();
    } catch (e) {
      debugPrint('[WatchSyncService] init error: $e');
    }
  }

  Future<void> _checkPhoneConnection() async {
    try {
      final nodes = await _connectivity.getConnectedDevices();
      _phoneConnected = nodes.isNotEmpty;
      notifyListeners();
    } catch (e) {
      _phoneConnected = false;
      debugPrint('[WatchSyncService] _checkPhoneConnection: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming message listener (phone -> watch)
  // ---------------------------------------------------------------------------
  void _listenToMessages() {
    _messageSub = _connectivity.messageReceived().listen(
      (WearOsMessage message) {
        final path = message.path;
        final data = message.data;

        if (path == SyncConstants.playbackState) {
          _handlePlaybackState(data);
        } else if (path == SyncConstants.libraryData) {
          _handleLibraryData(data);
        } else if (path == SyncConstants.searchResults) {
          _handleSearchResults(data);
        } else if (path == SyncConstants.downloadProgress) {
          _handleDownloadProgress(data);
        }
      },
      onError: (e) => debugPrint('[WatchSyncService] message error: $e'),
    );
  }

  // ---------------------------------------------------------------------------
  // Data layer listener — large payloads (library / download list)
  // ---------------------------------------------------------------------------
  void _listenToDataLayer() {
    _dataSub = _connectivity.dataChanged().listen(
      (DataEvent event) {
        final item = event.dataItem;
        // flutter_wear_os_connectivity exposes the path via `uri`.
        final path = item.uri.path ?? '';
        final payload = item.mapData;

        if (path == SyncConstants.dataLibrary) {
          _handleLibraryDataItem(payload);
        } else if (path == SyncConstants.dataDownloads) {
          _handleDownloadsDataItem(payload);
        }
      },
      onError: (e) => debugPrint('[WatchSyncService] data error: $e'),
    );
  }

  // ---------------------------------------------------------------------------
  // Handlers for incoming data
  // ---------------------------------------------------------------------------
  void _handlePlaybackState(Uint8List? data) {
    if (data == null || data.isEmpty) return;
    try {
      final map =
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final command = map['command'] as String?;
      final player = GetIt.I<WatchMediaPlayer>();

      switch (command) {
        case SyncConstants.cmdPlay:
          player.play();
        case SyncConstants.cmdPause:
          player.pause();
        case SyncConstants.cmdNext:
          player.seekToNext();
        case SyncConstants.cmdPrev:
          player.seekToPrevious();
        case SyncConstants.cmdSeek:
          final posMs = map['position'] as int?;
          if (posMs != null) {
            player.seek(Duration(milliseconds: posMs));
          }
      }
    } catch (e) {
      debugPrint('[WatchSyncService] _handlePlaybackState: $e');
    }
  }

  void _handleLibraryData(Uint8List? data) {
    if (data == null || data.isEmpty) return;
    try {
      final decoded =
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      _parseLibraryPayload(decoded);
    } catch (e) {
      debugPrint('[WatchSyncService] _handleLibraryData: $e');
    }
  }

  void _handleLibraryDataItem(Map<String, dynamic> payload) {
    try {
      _parseLibraryPayload(payload);
    } catch (e) {
      debugPrint('[WatchSyncService] _handleLibraryDataItem: $e');
    }
  }

  void _parseLibraryPayload(Map<String, dynamic> decoded) {
    final rawPlaylists = decoded['playlists'];
    final rawFavourites = decoded['favourites'];

    if (rawPlaylists is List) {
      _playlists = rawPlaylists
          .whereType<Map>()
          .map((e) => PlaylistModel.fromMap(e))
          .toList();
    }

    if (rawFavourites is List) {
      _favourites = rawFavourites
          .whereType<Map>()
          .map((e) => SongModel.fromMap(e))
          .toList();

      // Persist favourites list to the WATCH_LIBRARY Hive box so it's
      // available offline after the watch disconnects from the phone.
      final box = Hive.box('WATCH_LIBRARY');
      box.put(
        'favourites',
        _favourites.map((s) => s.toMap()).toList(),
      );
    }

    notifyListeners();
  }

  void _handleDownloadsDataItem(Map<String, dynamic> payload) {
    try {
      final rawDownloads = payload['downloads'];
      if (rawDownloads is! List) return;

      final box = Hive.box('WATCH_DOWNLOADS');
      for (final rawItem in rawDownloads.whereType<Map>()) {
        final item = DownloadItemModel.fromMap(rawItem);
        box.put(item.videoId, item.toMap());
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[WatchSyncService] _handleDownloadsDataItem: $e');
    }
  }

  void _handleSearchResults(Uint8List? data) {
    if (data == null || data.isEmpty) return;
    try {
      final decoded =
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final rawResults = decoded['results'];
      if (rawResults is List) {
        _searchResults = rawResults
            .whereType<Map>()
            .map((e) => SongModel.fromMap(e))
            .toList();
        _searchResultsController.add(_searchResults);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[WatchSyncService] _handleSearchResults: $e');
    }
  }

  void _handleDownloadProgress(Uint8List? data) {
    if (data == null || data.isEmpty) return;
    try {
      final map =
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final videoId = map['videoId'] as String?;
      final progress = (map['progress'] as num?)?.toDouble();
      if (videoId != null && progress != null) {
        _downloadProgress[videoId] = progress;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[WatchSyncService] _handleDownloadProgress: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming audio file via ChannelClient
  // ---------------------------------------------------------------------------

  /// Called when the phone pushes an audio file to the watch. The file bytes
  /// are written to the app's documents directory and the WATCH_DOWNLOADS Hive
  /// box is updated with the new local path.
  Future<void> receiveAudioFile({
    required String videoId,
    required String fileName,
    required Uint8List bytes,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/downloads/$fileName';
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      final box = Hive.box('WATCH_DOWNLOADS');
      final existing = box.get(videoId);
      final Map<String, dynamic> entry = existing != null
          ? Map<String, dynamic>.from(existing as Map)
          : (metadata != null ? Map<String, dynamic>.from(metadata) : {});

      entry['videoId'] = videoId;
      entry['path'] = filePath;
      entry['status'] = 'DOWNLOADED';

      box.put(videoId, entry);
      notifyListeners();
      debugPrint('[WatchSyncService] saved $fileName to $filePath');
    } catch (e) {
      debugPrint('[WatchSyncService] receiveAudioFile error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Outgoing commands (watch -> phone)
  // ---------------------------------------------------------------------------

  /// Send a playback command (play, pause, next, prev, seek) to the phone.
  Future<void> sendPlaybackCommand(
    String command, {
    int? seekPositionMs,
  }) async {
    try {
      final payload = <String, dynamic>{'command': command};
      if (seekPositionMs != null) payload['position'] = seekPositionMs;
      final data = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      await _connectivity.sendMessage(
        data,
        path: SyncConstants.playbackCommand,
      );
    } catch (e) {
      debugPrint('[WatchSyncService] sendPlaybackCommand error: $e');
    }
  }

  /// Send a search query string to the phone and wait for
  /// searchResultsStream to deliver the results.
  Future<void> sendSearchQuery(String query) async {
    try {
      final data = Uint8List.fromList(
        utf8.encode(jsonEncode({'query': query})),
      );
      await _connectivity.sendMessage(
        data,
        path: SyncConstants.searchQuery,
      );
    } catch (e) {
      debugPrint('[WatchSyncService] sendSearchQuery error: $e');
    }
  }

  /// Request the phone to push the full library (playlists + favourites).
  Future<void> requestLibrarySync() async {
    try {
      final data = Uint8List.fromList(utf8.encode('{}'));
      await _connectivity.sendMessage(
        data,
        path: SyncConstants.librarySync,
      );
    } catch (e) {
      debugPrint('[WatchSyncService] requestLibrarySync error: $e');
    }
  }

  /// Request the phone to download and push a specific song.
  Future<void> requestDownload(SongModel song) async {
    try {
      final data = Uint8List.fromList(
        utf8.encode(jsonEncode(song.toMap())),
      );
      await _connectivity.sendMessage(
        data,
        path: SyncConstants.downloadRequest,
      );
    } catch (e) {
      debugPrint('[WatchSyncService] requestDownload error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns all locally downloaded songs from the WATCH_DOWNLOADS Hive box.
  List<SongModel> getLocalDownloads() {
    if (!Hive.isBoxOpen('WATCH_DOWNLOADS')) return [];
    final box = Hive.box('WATCH_DOWNLOADS');
    return box.values
        .whereType<Map>()
        .map((e) => SongModel.fromMap(e))
        .where((s) => s.isDownloaded && s.path != null)
        .toList();
  }

  /// Returns the total bytes used by synced audio files.
  Future<int> computeStorageUsedBytes() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final downloads = Directory('${dir.path}/downloads');
      if (!downloads.existsSync()) return 0;
      int total = 0;
      await for (final entity in downloads.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    _messageSub?.cancel();
    _dataSub?.cancel();
    _searchResultsController.close();
    super.dispose();
  }
}
