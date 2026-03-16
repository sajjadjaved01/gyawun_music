import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun/core/constants/app_constants.dart';
import 'package:gyawun/services/yt_audio_stream.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import 'package:yt_music/ytmusic.dart';

import '../utils/add_history.dart';
import 'settings_manager.dart';

class MediaPlayer extends ChangeNotifier {
  late final AudioPlayer _player;

  final _loudnessEnhancer = AndroidLoudnessEnhancer();
  AndroidEqualizer? _equalizer;
  AndroidEqualizerParameters? _equalizerParams;

  List<IndexedAudioSource> _songList = [];
  final ValueNotifier<MediaItem?> _currentSongNotifier = ValueNotifier(null);
  final ValueNotifier<int?> _currentIndex = ValueNotifier(null);
  final ValueNotifier<ButtonState> _buttonState =
      ValueNotifier(ButtonState.loading);
  Timer? _timer;
  Timer? _statsTimer;
  Timer? _sleepFadeTimer;
  StreamSubscription<PlayerState>? _endOfTrackSub;
  final ValueNotifier<Duration?> _timerDuration = ValueNotifier(null);
  final ValueNotifier<bool> _endOfTrackMode = ValueNotifier(false);

  final ValueNotifier<LoopMode> _loopMode = ValueNotifier(LoopMode.off);

  final ValueNotifier<ProgressBarState> _progressBarState =
      ValueNotifier(ProgressBarState());

  bool _shuffleModeEnabled = false;

  bool autoFetching = false;

  // Crossfade state
  Timer? _crossfadeTimer;
  bool _isFadingOut = false;
  bool _isFadingIn = false;
  int? _fadeOutTriggeredForIndex;

  MediaPlayer() {
    if (Platform.isAndroid) {
      _equalizer = AndroidEqualizer();
    }
    final AudioPipeline pipeline = AudioPipeline(
      androidAudioEffects: [
        if (Platform.isAndroid && _equalizer != null) _equalizer!,
        _loudnessEnhancer,
      ],
    );
    _player = AudioPlayer(audioPipeline: pipeline);

    GetIt.I.registerSingleton<AndroidLoudnessEnhancer>(_loudnessEnhancer);
    if (Platform.isAndroid && _equalizer != null) {
      GetIt.I.registerSingleton<AndroidEqualizer>(_equalizer!);

    }

    _init();
  }

  AudioPlayer get player => _player;
  List<IndexedAudioSource> get songList => List.unmodifiable(_songList);
  ValueNotifier<MediaItem?> get currentSongNotifier => _currentSongNotifier;
  ValueNotifier<int?> get currentIndex => _currentIndex;
  ValueNotifier<ButtonState> get buttonState => _buttonState;
  ValueNotifier<ProgressBarState> get progressBarState => _progressBarState;
  bool get shuffleModeEnabled => _shuffleModeEnabled;
  ValueNotifier<LoopMode> get loopMode => _loopMode;
  ValueNotifier<Duration?> get timerDuration => _timerDuration;
  ValueNotifier<bool> get endOfTrackMode => _endOfTrackMode;

  Stream<
      ({
        List<IndexedAudioSource>? sequence,
        int? currentIndex,
        MediaItem? currentItem
      })> get currentTrackStream => Rx.combineLatest2<
          List<IndexedAudioSource>?,
          int?,
          ({
            List<IndexedAudioSource>? sequence,
            int? currentIndex,
            MediaItem? currentItem
          })>(
        _player.sequenceStream,
        _player.currentIndexStream,
        (sequence, currentIndex) {
          MediaItem? currentItem;
          if (sequence != null &&
              currentIndex != null &&
              currentIndex >= 0 &&
              currentIndex < sequence.length) {
            final tag = sequence[currentIndex].tag;
            if (tag is MediaItem) currentItem = tag;
          }
          return (
            sequence: sequence,
            currentIndex: currentIndex,
            currentItem: currentItem,
          );
        },
      );

  Future<void> _init() async {
    await _loadLoudnessEnhancer();
    await _loadEqualizer();

    // Start with an empty queue
    await _player.setAudioSources([]);

    _listenToChangesInPlaylist();
    _listenToPlaybackState();
    _listenToCurrentPosition();
    _listenToBufferedPosition();
    _listenToTotalDuration();
    _listenToChangesInSong();
    _listenToShuffle();
    _listenToAutofetch();
    _listenForCrossfade();

    _statsTimer = Timer.periodic(AppConstants.statsReportInterval, (timer) {
      if (currentSongNotifier.value != null && _player.playing) {
        GetIt.I<YTMusic>()
            .addPlayingStats(currentSongNotifier.value!.id, _player.position);
      }
    });
  }

  Future<void> _loadLoudnessEnhancer() async {
    await _loudnessEnhancer
        .setEnabled(GetIt.I<SettingsManager>().loudnessEnabled);

    await _loudnessEnhancer
        .setTargetGain(GetIt.I<SettingsManager>().loudnessTargetGain);
  }

  Future<void> _loadEqualizer() async {
    if (!Platform.isAndroid || _equalizer == null) return;
    await _equalizer!.setEnabled(GetIt.I<SettingsManager>().equalizerEnabled);
    _equalizer!.parameters.then((value) async {
      _equalizerParams ??= value;
      final List<AndroidEqualizerBand> bands = _equalizerParams!.bands;
      if (GetIt.I<SettingsManager>().equalizerBandsGain.isEmpty) {
        GetIt.I<SettingsManager>().equalizerBandsGain =
            List.generate(bands.length, (index) => 0.0);
      }

      List<double> equalizerBandsGain =
          GetIt.I<SettingsManager>().equalizerBandsGain;
      for (var e in bands) {
        final gain =
            equalizerBandsGain.isNotEmpty ? equalizerBandsGain[e.index] : 0.0;
        _equalizerParams!.bands[e.index].setGain(gain);
      }
    });
  }

  Future<void> setLoudnessEnabled(bool value) async {
    await _loudnessEnhancer.setEnabled(value);
    GetIt.I<SettingsManager>().loudnessEnabled = value;
  }

  Future<void> setEqualizerEnabled(bool value) async {
    await _equalizer?.setEnabled(value);
    GetIt.I<SettingsManager>().equalizerEnabled = value;
  }

  Future<void> setLoudnessTargetGain(double value) async {
    await _loudnessEnhancer.setTargetGain(value);
    GetIt.I<SettingsManager>().loudnessTargetGain = value;
  }

  void _listenToChangesInPlaylist() {
    _player.sequenceStream.listen((playlist) {
      final List<IndexedAudioSource> newList =
          (playlist).cast<IndexedAudioSource>();

      if (listEquals(newList, _songList)) return;

      final bool shouldAdd = (_songList.isEmpty && newList.isNotEmpty);

      if (newList.isEmpty) {
        _currentSongNotifier.value = null;
        _currentIndex.value = null;
        _songList = [];
      } else {
        _songList = newList;

        _currentIndex.value ??= 0;
        _currentSongNotifier.value =
            (_songList.length > (_currentIndex.value ?? 0))
                ? _songList[_currentIndex.value ?? 0].tag
                : null;
      }

      if (shouldAdd == true && _currentSongNotifier.value != null) {
        addHistory(_currentSongNotifier.value!.extras!);
      }

      notifyListeners();
    });
  }

  void _listenToPlaybackState() {
    _player.playerStateStream.listen((event) {
      final isPlaying = event.playing;
      final processingState = event.processingState;
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        _buttonState.value = ButtonState.loading;
      } else if (!isPlaying || processingState == ProcessingState.idle) {
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
      final oldState = _progressBarState.value;
      if (oldState.current != position) {
        _progressBarState.value = ProgressBarState(
          current: position,
          buffered: oldState.buffered,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToBufferedPosition() {
    _player.bufferedPositionStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.buffered != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: position,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToTotalDuration() {
    _player.durationStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.total != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: oldState.buffered,
          total: position ?? Duration.zero,
        );
      }
    });
  }

  void _listenToShuffle() {
    _player.shuffleModeEnabledStream.listen((data) {
      _shuffleModeEnabled = data;
      notifyListeners();
    });
  }

  void _listenToChangesInSong() {
    _player.currentIndexStream.listen((index) {
      if (_songList.isNotEmpty && _currentIndex.value != index) {
        _currentIndex.value = index;
        _currentSongNotifier.value =
            index != null && _songList.isNotEmpty && index < _songList.length
                ? _songList[index].tag
                : null;
        if (_songList.isNotEmpty && _currentIndex.value != null) {
          final MediaItem item = _songList[_currentIndex.value!].tag;
          addHistory(item.extras!);
        }
        notifyListeners();
      }
    });
  }

  void changeLoopMode() {
    switch (_loopMode.value) {
      case LoopMode.off:
        _loopMode.value = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode.value = LoopMode.one;
        break;
      default:
        _loopMode.value = LoopMode.off;
        break;
    }
    _player.setLoopMode(_loopMode.value);
  }

  Future<void> skipSilence(bool value) async {
    await _player.setSkipSilenceEnabled(value);
    GetIt.I<SettingsManager>().skipSilence = value;
  }

  Future<AudioSource> _getAudioSource(Map<String, dynamic> song) async {
    MediaItem tag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(
          song['thumbnails']?.first['url'].replaceAll('w60-h60', 'w225-h225')),
      artist: song['artists']?.map((artist) => artist['name']).join(','),
      extras: song,
    );

    final bool isDownloaded = song['status'] == 'DOWNLOADED' &&
        song['path'] != null &&
        (await File(song['path']).exists());

    if (isDownloaded) {
      return AudioSource.file(song['path'], tag: tag);
    } else {
      return YouTubeAudioSource(
        videoId: song['videoId'],
        quality: GetIt.I<SettingsManager>().streamingQuality.name.toLowerCase(),
        tag: tag,
      );
    }
  }

  Future<void> playSong(Map<String, dynamic> song) async {
    if (song['videoId'] == null) return;
    _cancelCrossfade();
    final source = await _getAudioSource(song);
    await _player.setAudioSource(source);
    await _player.play();
  }

  Future<void> playNext(Map<String, dynamic> mediaItem) async {
    // Case 1: A single video/song
    if (mediaItem['videoId'] != null) {
      final audioSource = await _getAudioSource(mediaItem);

      // Determine insertion position
      final currentIndex = _player.currentIndex ?? -1;
      final sequenceLength = _player.sequence.length;
      final insertIndex = (currentIndex + 1).clamp(0, sequenceLength);

      // If player already has something in the queue
      if (sequenceLength > 0) {
        await _player.insertAudioSource(insertIndex, audioSource);
      } else {
        // If queue is empty, just set and start playing
        await _player.setAudioSource(audioSource);
      }

      // Case 2: Custom or Downloaded Playlist
    } else if (mediaItem['songs'] != null) {
      List songs = mediaItem['songs'];
      await _addSongListToQueue(songs, isNext: true);

      // Case 3: Online Playlist
    } else if (mediaItem['playlistId'] != null) {
      List songs = mediaItem['type'] == 'ARTIST'
          ? await GetIt.I<YTMusic>()
              .getNextSongList(playlistId: mediaItem['playlistId'])
          : await GetIt.I<YTMusic>().getPlaylistSongs(mediaItem['playlistId']);
      await _addSongListToQueue(songs, isNext: true);
    }
  }

  Future<void> playAll(List songs, {int index = 0}) async {
    _cancelCrossfade();
    // Build full list and set atomically
    final List<AudioSource> sources = [];
    for (final s in songs) {
      sources.add(await _getAudioSource(Map<String, dynamic>.from(s)));
    }

    await _player.setAudioSources(sources);
    await _player.seek(Duration.zero, index: index);
    if (!_player.playing) await _player.play();
  }

  Future<void> addToQueue(Map<String, dynamic> mediaItem) async {
    // Case 1: A single video/song
    if (mediaItem['videoId'] != null) {
      await _player.addAudioSource(await _getAudioSource(mediaItem));

      // Case 2: Custom or Downloaded Playlist
    } else if (mediaItem['songs'] != null) {
      List songs = mediaItem['songs'];
      await _addSongListToQueue(songs, isNext: false);

      // Case 3: Online Playlist
    } else if (mediaItem['playlistId'] != null) {
      List songs = mediaItem['type'] == 'ARTIST'
          ? await GetIt.I<YTMusic>()
              .getNextSongList(playlistId: mediaItem['playlistId'])
          : await GetIt.I<YTMusic>().getPlaylistSongs(mediaItem['playlistId']);
      await _addSongListToQueue(songs, isNext: false);
    }
  }

  Future<void> startRelated(Map<String, dynamic> song,
      {bool radio = false, bool shuffle = false, bool isArtist = false}) async {
    await _player.clearAudioSources();
    if (!isArtist) {
      await addToQueue(song);
    }
    List songs = await GetIt.I<YTMusic>().getNextSongList(
        videoId: song['videoId'],
        playlistId: song['playlistRadioId'],
        radio: radio,
        shuffle: shuffle);
    if (songs.isNotEmpty) songs.removeAt(0);
    await _addSongListToQueue(songs, isNext: false);
    await _player.play();
  }

  Future<void> startPlaylistSongs(Map endpoint) async {
    await _player.clearAudioSources();
    List songs = await GetIt.I<YTMusic>().getNextSongList(
        playlistId: endpoint['playlistId'], params: endpoint['params']);

    if (songs.isNotEmpty && songs.first['videoId'] == null) {
      // if API returned a placeholder, convert or handle accordingly
    }

    await _addSongListToQueue(songs);
    await _player.play();
  }

  Future<void> stop() async {
    _cancelCrossfade();
    await _player.stop();
    await _player.clearAudioSources();
    await _player.seek(Duration.zero, index: 0);
    _currentIndex.value = null;
    _currentSongNotifier.value = null;
    notifyListeners();
  }

  Future<void> _addSongListToQueue(List songs, {bool isNext = false}) async {
    if (songs.isEmpty) return;

    // Convert your song objects into AudioSources
    final newSources = await Future.wait(songs.map((song) async {
      final mapSong = Map<String, dynamic>.from(song);
      return await _getAudioSource(mapSong);
    }));
    

    // Current queue length
    final queueLength = _player.sequence.length;

    if (isNext) {
      // Insert immediately after the current index
      final currentIndex = _player.currentIndex ?? -1;
      int insertIndex = (currentIndex + 1).clamp(0, queueLength);
      await _player.insertAudioSources(insertIndex, newSources);
    } else {
      // Append to the end
      await _player.addAudioSources(newSources);
    }
  }

  void _listenToAutofetch() {
    player.currentIndexStream.listen((index)async{
      if(index==null) return;
      if(player.sequence.length-index<5 && GetIt.I<SettingsManager>().autofetchSongs && autoFetching==false){
        autoFetching = true;
        List nextSongs = await GetIt.I<YTMusic>().getNextSongList(
            videoId: player.sequence[index].tag.id);
        if (nextSongs.isNotEmpty) nextSongs.removeAt(0);
        await _addSongListToQueue(nextSongs);
        autoFetching=false;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Sleep timer
  // ---------------------------------------------------------------------------

  /// Volume fade duration applied when the sleep timer reaches its last 30 s.
  static const int _sleepFadeSeconds = 30;

  /// Start a countdown sleep timer. Pauses playback when [duration] expires.
  /// When [GetIt.I<SettingsManager>().sleepTimerFadeOut] is true and the timer
  /// still has 30 s or more remaining, volume is faded out in the last 30 s
  /// before pausing.
  void setTimer(Duration duration) {
    _cancelSleepTimer();
    int seconds = duration.inSeconds;
    _timerDuration.value = duration;
    _endOfTrackMode.value = false;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      seconds--;
      _timerDuration.value = Duration(seconds: seconds);

      final bool fadeEnabled = GetIt.I<SettingsManager>().sleepTimerFadeOut;
      // Kick off the fade only once, exactly when `_sleepFadeSeconds` remain.
      if (fadeEnabled &&
          seconds == _sleepFadeSeconds &&
          _sleepFadeTimer == null) {
        _startSleepFade();
      }

      if (seconds <= 0) {
        _onSleepTimerExpired();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// Arm "finish current song then stop" mode.
  /// Pauses (with optional fade) after the currently-playing track completes.
  void setEndOfTrackTimer() {
    _cancelSleepTimer();
    _endOfTrackMode.value = true;
    _timerDuration.value = null;

    _endOfTrackSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onSleepTimerExpired();
      }
    });
    notifyListeners();
  }

  void cancelTimer() {
    _cancelSleepTimer();
    notifyListeners();
  }

  // Tears down all sleep-timer state without firing notifyListeners.
  void _cancelSleepTimer() {
    _timer?.cancel();
    _timer = null;
    // Restore volume only if a sleep fade was actively running.
    final bool wasF = _sleepFadeTimer != null;
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = null;
    _endOfTrackSub?.cancel();
    _endOfTrackSub = null;
    _timerDuration.value = null;
    _endOfTrackMode.value = false;
    if (wasF) {
      _player.setVolume(1.0);
    }
  }

  /// Gradually reduce volume to 0 over [_sleepFadeSeconds] seconds (500 ms steps).
  void _startSleepFade() {
    _sleepFadeTimer?.cancel();
    final double startVolume = _player.volume;
    // 60 steps over 30 s at 500 ms each.
    const int steps = 60;
    final double stepSize = startVolume / steps;
    int elapsed = 0;

    _sleepFadeTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      elapsed++;
      final double newVolume =
          (startVolume - stepSize * elapsed).clamp(0.0, 1.0);
      _player.setVolume(newVolume);
      if (newVolume <= 0.0) {
        timer.cancel();
      }
    });
  }

  void _onSleepTimerExpired() {
    _timer?.cancel();
    _timer = null;
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = null;
    _endOfTrackSub?.cancel();
    _endOfTrackSub = null;
    _timerDuration.value = null;
    _endOfTrackMode.value = false;

    _player.pause().then((_) {
      // Always restore to full volume so the next listening session is normal.
      _player.setVolume(1.0);
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Crossfade
  // ---------------------------------------------------------------------------

  void _listenForCrossfade() {
    // Monitor position to trigger fade-out near end of track.
    _player.positionStream.listen((position) {
      final crossfadeSeconds =
          GetIt.I<SettingsManager>().crossfadeDuration;
      if (crossfadeSeconds == 0) return;

      final duration = _player.duration;
      if (duration == null || duration == Duration.zero) return;

      // Only fade when actually playing and not looping a single song.
      if (!_player.playing) return;
      if (_loopMode.value == LoopMode.one) return;

      final currentIdx = _player.currentIndex;
      final sequenceLength = _player.sequence.length;

      // Don't fade out on the last track if loop is off (nothing to cross into).
      if (_loopMode.value == LoopMode.off &&
          currentIdx != null &&
          currentIdx >= sequenceLength - 1) {
        return;
      }

      final remaining = duration - position;
      final fadeWindow = Duration(seconds: crossfadeSeconds);

      if (remaining <= fadeWindow &&
          !_isFadingOut &&
          _fadeOutTriggeredForIndex != currentIdx) {
        _fadeOutTriggeredForIndex = currentIdx;
        _startFadeOut(crossfadeSeconds, remaining);
      }
    });

    // When the track index changes, fade in the new track.
    _player.currentIndexStream.listen((index) {
      if (index == null) return;
      final crossfadeSeconds =
          GetIt.I<SettingsManager>().crossfadeDuration;
      if (crossfadeSeconds == 0) return;

      // If we were fading out, the track changed — now fade in.
      if (_isFadingOut || _player.volume < 1.0) {
        _isFadingOut = false;
        _crossfadeTimer?.cancel();
        _startFadeIn(crossfadeSeconds);
      }
    });
  }

  void _startFadeOut(int durationSeconds, Duration remaining) {
    _isFadingOut = true;
    _crossfadeTimer?.cancel();

    final totalSteps = durationSeconds * 20; // 20 ticks per second (50 ms)
    final stepInterval = const Duration(milliseconds: 50);
    final startVolume = _player.volume;
    int step = 0;

    _crossfadeTimer = Timer.periodic(stepInterval, (timer) {
      if (!_isFadingOut) {
        timer.cancel();
        return;
      }
      step++;
      final progress = step / totalSteps;
      final newVolume = (startVolume * (1.0 - progress)).clamp(0.0, 1.0);
      _player.setVolume(newVolume);

      if (progress >= 1.0 || newVolume <= 0.0) {
        timer.cancel();
        // Don't reset _isFadingOut here; track-change listener will do that.
      }
    });
  }

  void _startFadeIn(int durationSeconds) {
    _isFadingIn = true;
    _crossfadeTimer?.cancel();

    // Ensure we start silent so the fade-in is audible.
    _player.setVolume(0.0);

    final totalSteps = durationSeconds * 20;
    final stepInterval = const Duration(milliseconds: 50);
    int step = 0;

    _crossfadeTimer = Timer.periodic(stepInterval, (timer) {
      if (!_isFadingIn) {
        timer.cancel();
        return;
      }
      step++;
      final progress = step / totalSteps;
      final newVolume = progress.clamp(0.0, 1.0);
      _player.setVolume(newVolume);

      if (progress >= 1.0) {
        _isFadingIn = false;
        timer.cancel();
      }
    });
  }

  /// Reset any in-progress crossfade and restore full volume.
  /// Called when the user manually seeks, skips, or changes tracks.
  void _cancelCrossfade() {
    _crossfadeTimer?.cancel();
    _isFadingOut = false;
    _isFadingIn = false;
    _fadeOutTriggeredForIndex = null;
    _player.setVolume(1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statsTimer?.cancel();
    _sleepFadeTimer?.cancel();
    _endOfTrackSub?.cancel();
    _crossfadeTimer?.cancel();
    _player.dispose();
    _currentSongNotifier.dispose();
    _currentIndex.dispose();
    _buttonState.dispose();
    _timerDuration.dispose();
    _endOfTrackMode.dispose();
    _loopMode.dispose();
    _progressBarState.dispose();
    super.dispose();
  }
}

enum ButtonState { loading, paused, playing }

enum LoopState { off, all, one }

class ProgressBarState {
  Duration current;
  Duration buffered;
  Duration total;
  ProgressBarState(
      {this.current = Duration.zero,
      this.buffered = Duration.zero,
      this.total = Duration.zero});
}
