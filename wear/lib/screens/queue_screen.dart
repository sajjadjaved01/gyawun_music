import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import '../services/watch_media_player.dart';
import '../widgets/rotary_scroll_controller.dart';

// ---------------------------------------------------------------------------
// QueueScreen
// Scrollable list of queued tracks with rotary crown/bezel support.
// The currently playing track is highlighted in the accent colour.
// ---------------------------------------------------------------------------
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  @override
  Widget build(BuildContext context) {
    final player = context.watch<WatchMediaPlayer>();
    final queue = player.songList;

    if (queue.isEmpty) {
      return const _EmptyQueue();
    }

    return ValueListenableBuilder<int?>(
      valueListenable: player.currentIndex,
      builder: (context, currentIdx, _) {
        return RotaryScrollWrapper(
          child: (controller) => ListView.builder(
            controller: controller,
            padding: const EdgeInsets.symmetric(vertical: 24),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final source = queue[index];
              final tag = source.tag;
              final mediaItem = tag is MediaItem ? tag : null;
              final isActive = index == currentIdx;

              return _QueueTile(
                title: mediaItem?.title ?? 'Track ${index + 1}',
                artist: mediaItem?.artist ?? '',
                isActive: isActive,
                onTap: () => player.seekToIndex(index),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.queue_music, color: Color(0xFF555555), size: 36),
          SizedBox(height: 8),
          Text(
            'Queue is empty',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual queue tile
// ---------------------------------------------------------------------------
class _QueueTile extends StatelessWidget {
  final String title;
  final String artist;
  final bool isActive;
  final VoidCallback onTap;

  const _QueueTile({
    required this.title,
    required this.artist,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF1DB954);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? accentColor.withAlpha(40)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: accentColor, width: 1)
              : null,
        ),
        child: Row(
          children: [
            // Now-playing indicator dot
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? accentColor : Colors.transparent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? accentColor : Colors.white,
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (artist.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      artist,
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
