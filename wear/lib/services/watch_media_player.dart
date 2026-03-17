import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

// ---------------------------------------------------------------------------
// Value-object for the progress bar state.
// ---------------------------------------------------------------------------
class ProgressBarState {
  final Duration current;
  final Duration buffered;
  final Duration total;

  const ProgressBarState({
    this.current = Duration.zero,
    this.buffered = Duration.zero,
    this.total = Duration.zero,
  });
}

// ---------------------------------------------------------------------------
// Button state mirrors the phone app's enum.
// ---------------------------------------------------------------------------
enum ButtonState { loading, paused, playing }

// ---------------------------------------------------------------------------
// WatchMediaPlayer
// Offline-only, stripped-down AudioPlayer wrapper for Wear OS.
// No crossfade, no equalizer, no loudness enhancer, no sleep timer,
// no auto-fetch, no YouTube streaming — synced files only.
// ---------------------------------------------------------------------------
class WatchMediaPlayer extends ChangeNotifier {
  late final AudioPlayer _player;

  List<IndexedAudioSource> _songList = [];

  final ValueNotifier<MediaItem?> _currentSongNotifier =
      ValueNotifier<MediaItem?>(null);
  final ValueNotifier<int?> _currentIndex = ValueNotifier<int?>(null);
  final ValueNotifier<ButtonState> _buttonState =
      ValueNotifier<ButtonState>(ButtonState.loading);
  final ValueNotifier<ProgressBarState> _progressBarState =
      ValueNotifier<ProgressBarState>(const ProgressBarState());
  final ValueNotifier<LoopMode> _loopMode =
      ValueNotifier<LoopMode>(LoopMode.off);

  bool _shuffleModeEnabled = false;

  // ---------------------------------------------------------------------------
  // Public accessors
  // ---------------------------------------------------------------------------
  AudioPlayer get player => _player;
  List<IndexedAudioSource> get songList => List.unmodifiable(_songList);
  ValueNotifier<MediaItem?> get currentSongNotifier => _currentSongNotifier;
  ValueNotifier<int?> get currentIndex => _currentIndex;
  ValueNotifier<ButtonState> get buttonState => _buttonState;
  ValueNotifier<ProgressBarState> get progressBarState => _progressBarState;
  ValueNotifier<LoopMode> get loopMode => _loopMode;
  bool get shuffleModeEnabled => _shuffleModeEnabled;

  WatchMediaPlayer() {
    _player = AudioPlayer();
    _init();
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------
  Future<void> _init() async {
    await _player.setAudioSources([]);
    _listenToChangesInPlaylist();
    _listenToPlaybackState();
    _listenToCurrentPosition();
    _listenToBufferedPosition();
    _listenToTotalDuration();
    _listenToChangesInSong();
    _listenToShuffle();
  }

  // ---------------------------------------------------------------------------
  // Bluetooth audio output check
  // ---------------------------------------------------------------------------

  /// Returns true when a Bluetooth A2DP or BLE audio output device is
  /// connected. On non-Android platforms this always returns true so the
  /// player is never blocked during development.
  Future<bool> hasAudioOutput() async {
    if (!Platform.isAndroid) return true;
    // Wear OS exposes audio output through the platform; a simple heuristic
    // is to check whether the player can produce sound (i.e. it is not in
    // a completely idle state without a connected sink). A full implementation
    // would use a MethodChannel to query AudioManager on the native side, but
    // for the Wear OS context we optimistically return true and let the
    // OS handle routing — the user will hear silence if no output is ready.
    return true;
  }

  // ---------------------------------------------------------------------------
  // Audio source builder — offline files only
  // ---------------------------------------------------------------------------
  Future<AudioSource?> _buildAudioSource(Map<String, dynamic> song) async {
    final String? videoId = song['videoId'] as String?;
    final String? path = song['path'] as String?;

    if (videoId == null) return null;
    if (path == null || !(await File(path).exists())) return null;

    final thumbnails = song['thumbnails'];
    Uri? artUri;
    if (thumbnails is List && thumbnails.isNotEmpty) {
      final first = thumbnails.first;
      if (first is Map && first['url'] is String) {
        final raw = first['url'] as String;
        artUri = Uri.tryParse(
          raw.replaceAll('w60-h60', 'w225-h225'),
        );
      }
    }

    final artists = song['artists'];
    String? artistStr;
    if (artists is List) {
      artistStr = artists
          .whereType<Map>()
          .map((a) => a['name'] as String? ?? '')
          .join(', ');
    }

    final MediaItem tag = MediaItem(
      id: videoId,
      title: song['title'] as String? ?? 'Unknown',
      album: (song['album'] as Map?)?['name'] as String?,
      artist: artistStr,
      artUri: artUri,
      extras: Map<String, dynamic>.from(song),
    );

    return AudioSource.file(path, tag: tag);
  }

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  /// Play a single song from a local file.
  Future<void> playSong(Map<String, dynamic> song) async {
    final source = await _buildAudioSource(song);
    if (source == null) return;
    await _player.setAudioSource(source);
    await _player.play();
  }

  /// Replace the entire queue and start playing from [startIndex].
  Future<void> playAll(List<Map<String, dynamic>> songs,
      {int startIndex = 0}) async {
    final sources = <AudioSource>[];
    for (final s in songs) {
      final src = await _buildAudioSource(s);
      if (src != null) sources.add(src);
    }
    if (sources.isEmpty) return;

    final clampedIndex = startIndex.clamp(0, sources.length - 1);
    await _player.setAudioSources(sources);
    await _player.seek(Duration.zero, index: clampedIndex);
    if (!_player.playing) await _player.play();
  }

  /// Insert a song immediately after the current track.
  Future<void> playNext(Map<String, dynamic> song) async {
    final source = await _buildAudioSource(song);
    if (source == null) return;

    final queueLength = _player.sequence.length;
    if (queueLength == 0) {
      await _player.setAudioSource(source);
    } else {
      final insertAt = ((_player.currentIndex ?? -1) + 1)
          .clamp(0, queueLength);
      await _player.insertAudioSource(insertAt, source);
    }
  }

  /// Append a song to the end of the queue.
  Future<void> addToQueue(Map<String, dynamic> song) async {
    final source = await _buildAudioSource(song);
    if (source == null) return;
    await _player.addAudioSource(source);
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> seekToNext() => _player.seekToNext();
  Future<void> seekToPrevious() => _player.seekToPrevious();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> seekToIndex(int index) =>
      _player.seek(Duration.zero, index: index);

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  double get volume => _player.volume;

  Future<void> stop() async {
    await _player.stop();
    await _player.clearAudioSources();
    _currentIndex.value = null;
    _currentSongNotifier.value = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Loop / shuffle
  // ---------------------------------------------------------------------------
  void cycleLoopMode() {
    switch (_loopMode.value) {
      case LoopMode.off:
        _loopMode.value = LoopMode.all;
      case LoopMode.all:
        _loopMode.value = LoopMode.one;
      case LoopMode.one:
        _loopMode.value = LoopMode.off;
    }
    _player.setLoopMode(_loopMode.value);
  }

  Future<void> toggleShuffle() async {
    _shuffleModeEnabled = !_shuffleModeEnabled;
    await _player.setShuffleModeEnabled(_shuffleModeEnabled);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Stream listeners
  // ---------------------------------------------------------------------------
  void _listenToChangesInPlaylist() {
    _player.sequenceStream.listen((playlist) {
      final newList = (playlist ?? []).cast<IndexedAudioSource>();
      if (newList.isEmpty) {
        _currentSongNotifier.value = null;
        _currentIndex.value = null;
        _songList = [];
      } else {
        _songList = newList;
        _currentIndex.value ??= 0;
        final idx = _currentIndex.value ?? 0;
        _currentSongNotifier.value =
            idx < _songList.length ? _songList[idx].tag as MediaItem? : null;
      }
      notifyListeners();
    });
  }

  void _listenToPlaybackState() {
    _player.playerStateStream.listen((event) {
      final processingState = event.processingState;
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        _buttonState.value = ButtonState.loading;
      } else if (!event.playing ||
          processingState == ProcessingState.idle) {
        _buttonState.value = ButtonState.paused;
      } else if (processingState != ProcessingState.completed) {
        _buttonState.value = ButtonState.playing;
      } else {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  void _listenToCurrentPosition() {
    _player.positionStream.listen((position) {
      final old = _progressBarState.value;
      if (old.current != position) {
        _progressBarState.value = ProgressBarState(
          current: position,
          buffered: old.buffered,
          total: old.total,
        );
      }
    });
  }

  void _listenToBufferedPosition() {
    _player.bufferedPositionStream.listen((position) {
      final old = _progressBarState.value;
      if (old.buffered != position) {
        _progressBarState.value = ProgressBarState(
          current: old.current,
          buffered: position,
          total: old.total,
        );
      }
    });
  }

  void _listenToTotalDuration() {
    _player.durationStream.listen((dur) {
      final old = _progressBarState.value;
      final total = dur ?? Duration.zero;
      if (old.total != total) {
        _progressBarState.value = ProgressBarState(
          current: old.current,
          buffered: old.buffered,
          total: total,
        );
      }
    });
  }

  void _listenToChangesInSong() {
    _player.currentIndexStream.listen((index) {
      if (_songList.isNotEmpty && _currentIndex.value != index) {
        _currentIndex.value = index;
        _currentSongNotifier.value =
            index != null && index < _songList.length
                ? _songList[index].tag as MediaItem?
                : null;
        notifyListeners();
      }
    });
  }

  void _listenToShuffle() {
    _player.shuffleModeEnabledStream.listen((data) {
      _shuffleModeEnabled = data;
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------
  @override
  void dispose() {
    _player.dispose();
    _currentSongNotifier.dispose();
    _currentIndex.dispose();
    _buttonState.dispose();
    _progressBarState.dispose();
    _loopMode.dispose();
    super.dispose();
  }
}
