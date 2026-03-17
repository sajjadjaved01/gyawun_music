import 'package:flutter/material.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:provider/provider.dart';

import '../services/watch_media_player.dart';
import '../widgets/rotary_scroll_controller.dart';

// ---------------------------------------------------------------------------
// PlaylistScreen
// Displays an ordered list of songs for a Downloads collection, Favourites,
// or a user playlist. Tap plays from that position.
// ---------------------------------------------------------------------------
class PlaylistScreen extends StatefulWidget {
  final String title;
  final List<SongModel> songs;

  const PlaylistScreen({
    super.key,
    required this.title,
    required this.songs,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  @override
  Widget build(BuildContext context) {
    if (widget.songs.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_off_rounded,
                  color: Color(0xFF555555), size: 36),
              const SizedBox(height: 8),
              Text(
                widget.title,
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'No songs',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: RotaryScrollWrapper(
        child: (controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.only(top: 28, bottom: 16),
          itemCount: widget.songs.length + 1, // +1 for the header
          itemBuilder: (context, index) {
            if (index == 0) {
              return _PlaylistHeader(
                title: widget.title,
                count: widget.songs.length,
                onPlayAll: () => _playAll(context, 0),
              );
            }
            final song = widget.songs[index - 1];
            return _SongTile(
              song: song,
              onTap: () => _playAll(context, index - 1),
            );
          },
        ),
      ),
    );
  }

  Future<void> _playAll(BuildContext context, int startIndex) async {
    final player = context.read<WatchMediaPlayer>();
    final maps = widget.songs
        .map((s) => s.toMap())
        .toList();
    await player.playAll(
      maps.cast<Map<String, dynamic>>(),
      startIndex: startIndex,
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------
class _PlaylistHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onPlayAll;

  const _PlaylistHeader({
    required this.title,
    required this.count,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$count songs',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onPlayAll,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Play all',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Song tile
// ---------------------------------------------------------------------------
class _SongTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _SongTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Offline indicator
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF1DB954),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  if (song.artistNames.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      song.artistNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
