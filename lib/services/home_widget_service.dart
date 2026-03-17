import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'media_player.dart';

/// Keeps the Android home screen widget in sync with the current player state.
///
/// Call [init] once after [MediaPlayer] is created. The service attaches
/// [ValueNotifier] listeners to [MediaPlayer.currentSongNotifier] and
/// [MediaPlayer.buttonState] and pushes updates to the widget via the
/// `home_widget` package.
///
/// All methods are no-ops on platforms other than Android.
class HomeWidgetService {
  HomeWidgetService._();

  static const String _androidProvider =
      'com.jhelum.gyawun.MusicWidgetProvider';

  // Keys must match those read in MusicWidgetProvider.kt.
  // home_widget automatically prefixes all keys with "flutter." when writing
  // to FlutterSharedPreferences, which is where the Kotlin side reads them from.
  static const String _keyTitle = 'hw_title';
  static const String _keyArtist = 'hw_artist';
  static const String _keyArtUrl = 'hw_art_url';
  static const String _keyIsPlaying = 'hw_is_playing';

  static HomeWidgetService? _instance;
  static HomeWidgetService get instance =>
      _instance ??= HomeWidgetService._();

  MediaPlayer? _player;

  // Keep references so we can remove them on dispose.
  late final VoidCallback _songListener;
  late final VoidCallback _stateListener;

  MediaItem? _lastSong;
  ButtonState? _lastButtonState;

  /// Attach to [player] and start syncing widget data.
  void init(MediaPlayer player) {
    if (!Platform.isAndroid) return;

    _player = player;

    _songListener = () => _onStateChanged();
    _stateListener = () => _onStateChanged();

    player.currentSongNotifier.addListener(_songListener);
    player.buttonState.addListener(_stateListener);

    // Push the current state immediately in case the app is restarted while
    // a song is already loaded (e.g. from a media session restore).
    _onStateChanged();
  }

  void _onStateChanged() {
    final player = _player;
    if (player == null) return;

    final song = player.currentSongNotifier.value;
    final state = player.buttonState.value;
    final isPlaying = state == ButtonState.playing;

    // Skip redundant pushes.
    if (song == _lastSong && state == _lastButtonState) return;
    _lastSong = song;
    _lastButtonState = state;

    _pushUpdate(song: song, isPlaying: isPlaying);
  }

  Future<void> _pushUpdate({
    required MediaItem? song,
    required bool isPlaying,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>(_keyTitle, song?.title ?? ''),
        HomeWidget.saveWidgetData<String>(_keyArtist, song?.artist ?? ''),
        HomeWidget.saveWidgetData<String>(
          _keyArtUrl,
          song?.artUri?.toString() ?? '',
        ),
        HomeWidget.saveWidgetData<bool>(_keyIsPlaying, isPlaying),
      ]);

      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
    } catch (e) {
      debugPrint('[HomeWidgetService] Failed to update widget: $e');
    }
  }

  void dispose() {
    final player = _player;
    if (player != null) {
      player.currentSongNotifier.removeListener(_songListener);
      player.buttonState.removeListener(_stateListener);
    }
    _player = null;
  }
}
