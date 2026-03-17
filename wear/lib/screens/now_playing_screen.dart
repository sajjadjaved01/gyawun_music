import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:wearable_rotary/wearable_rotary.dart' as rotary;
import 'package:wear_plus/wear_plus.dart';

import '../services/watch_media_player.dart';
import '../widgets/circular_progress_indicator.dart';

// ---------------------------------------------------------------------------
// NowPlayingScreen
// Round Wear OS layout: album art circle + progress arc + controls.
// Rotary crown/bezel adjusts volume.
// Ambient mode: monochrome, no animations.
// ---------------------------------------------------------------------------
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<rotary.RotaryEvent>? _rotarySub;

  // Debounce volume notification to avoid rapid Hive writes.
  Timer? _volumeDebounce;

  @override
  void initState() {
    super.initState();
    _rotarySub = rotary.rotaryEvents.listen(_onRotaryVolume);
  }

  void _onRotaryVolume(rotary.RotaryEvent event) {
    final player = context.read<WatchMediaPlayer>();
    final current = player.volume;
    // 0.05 per notch, clamped 0.0 – 1.0.
    final next = (current + event.magnitude * 0.05).clamp(0.0, 1.0);
    player.setVolume(next);
  }

  @override
  void dispose() {
    _rotarySub?.cancel();
    _volumeDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return WatchShape(
      builder: (context, shape, child) => AmbientMode(
        builder: (context, mode) => _NowPlayingBody(ambientMode: mode),
      ),
    );
  }
}

class _NowPlayingBody extends StatelessWidget {
  final WearMode ambientMode;

  const _NowPlayingBody({required this.ambientMode});

  bool get isAmbient => ambientMode == WearMode.ambient;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<WatchMediaPlayer>();
    final size = MediaQuery.sizeOf(context);
    final screenDiameter = math.min(size.width, size.height);

    return ValueListenableBuilder<MediaItem?>(
      valueListenable: player.currentSongNotifier,
      builder: (context, mediaItem, _) {
        return ValueListenableBuilder<ProgressBarState>(
          valueListenable: player.progressBarState,
          builder: (context, progress, _) {
            final double progressValue =
                progress.total.inMilliseconds > 0
                    ? (progress.current.inMilliseconds /
                            progress.total.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Background
                Container(
                  width: screenDiameter,
                  height: screenDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAmbient ? Colors.black : const Color(0xFF121212),
                  ),
                ),

                // Progress arc around the bezel
                SizedBox(
                  width: screenDiameter,
                  height: screenDiameter,
                  child: PlaybackProgressArc(
                    progress: progressValue,
                    isAmbient: isAmbient,
                    strokeWidth: 5.0,
                    color: const Color(0xFF1DB954),
                  ),
                ),

                // Album art — circular, inset from arc
                Positioned(
                  child: _AlbumArt(
                    artUrl: mediaItem?.artUri?.toString(),
                    diameter: screenDiameter * 0.62,
                    isAmbient: isAmbient,
                  ),
                ),

                // Song info — title + artist
                Positioned(
                  bottom: screenDiameter * 0.22,
                  left: screenDiameter * 0.10,
                  right: screenDiameter * 0.10,
                  child: _SongInfo(
                    title: mediaItem?.title ?? 'Nothing playing',
                    artist: mediaItem?.artist ?? '',
                    isAmbient: isAmbient,
                  ),
                ),

                // Controls row — prev / play-pause / next
                if (!isAmbient)
                  Positioned(
                    bottom: screenDiameter * 0.06,
                    child: _ControlsRow(player: player),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Album art widget
// ---------------------------------------------------------------------------
class _AlbumArt extends StatelessWidget {
  final String? artUrl;
  final double diameter;
  final bool isAmbient;

  const _AlbumArt({
    required this.artUrl,
    required this.diameter,
    required this.isAmbient,
  });

  @override
  Widget build(BuildContext context) {
    Widget image;

    if (artUrl != null && artUrl!.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: artUrl!,
        fit: BoxFit.cover,
        width: diameter,
        height: diameter,
        placeholder: (_, __) => const _ArtPlaceholder(),
        errorWidget: (_, __, ___) => const _ArtPlaceholder(),
      );
    } else {
      image = const _ArtPlaceholder();
    }

    // Monochrome in ambient mode to conserve OLED power
    if (isAmbient) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: image,
      );
    }

    return ClipOval(
      child: SizedBox(width: diameter, height: diameter, child: image),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Icon(Icons.music_note, color: Color(0xFF888888), size: 40),
    );
  }
}

// ---------------------------------------------------------------------------
// Scrolling marquee for long song titles
// ---------------------------------------------------------------------------
class _SongInfo extends StatelessWidget {
  final String title;
  final String artist;
  final bool isAmbient;

  const _SongInfo({
    required this.title,
    required this.artist,
    required this.isAmbient,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor =
        isAmbient ? const Color(0xFFAAAAAA) : Colors.white;
    final artistColor =
        isAmbient ? const Color(0xFF666666) : const Color(0xFFAAAAAA);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: titleColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          artist,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: artistColor,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Playback controls
// ---------------------------------------------------------------------------
class _ControlsRow extends StatelessWidget {
  final WatchMediaPlayer player;

  const _ControlsRow({required this.player});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ButtonState>(
      valueListenable: player.buttonState,
      builder: (context, state, _) {
        final isLoading = state == ButtonState.loading;
        final isPlaying = state == ButtonState.playing;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Previous
            _ControlButton(
              icon: Icons.skip_previous_rounded,
              size: 28,
              onTap: () => player.seekToPrevious(),
            ),
            const SizedBox(width: 8),

            // Play / Pause — larger central button
            _ControlButton(
              icon: isLoading
                  ? null
                  : isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
              size: 38,
              isLoading: isLoading,
              onTap: () => player.togglePlayPause(),
            ),
            const SizedBox(width: 8),

            // Next
            _ControlButton(
              icon: Icons.skip_next_rounded,
              size: 28,
              onTap: () => player.seekToNext(),
            ),
          ],
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData? icon;
  final double size;
  final bool isLoading;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size + 16,
        height: size + 16,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: size * 0.7,
                  height: size * 0.7,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF1DB954),
                  ),
                )
              : Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}
