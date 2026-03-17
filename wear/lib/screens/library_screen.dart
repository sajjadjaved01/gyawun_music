import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun_shared/gyawun_shared.dart';

import '../services/watch_sync_service.dart';
import '../widgets/rotary_scroll_controller.dart';
import 'playlist_screen.dart';

// ---------------------------------------------------------------------------
// LibraryScreen
// Top-level entry points: Downloads, Favourites, and synced Playlists.
// ---------------------------------------------------------------------------
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with RotaryScrollMixin {
  WatchSyncService get _sync => GetIt.I<WatchSyncService>();

  @override
  Widget build(BuildContext context) {
    final downloads = _sync.getLocalDownloads();
    final favourites = _sync.favourites;
    final playlists = _sync.playlists;

    // Build the unified list of sections
    final sections = <_LibrarySection>[
      _LibrarySection(
        icon: Icons.download_done_rounded,
        label: 'Downloads',
        subtitle: '${downloads.length} songs',
        songs: downloads,
        color: const Color(0xFF1DB954),
      ),
      _LibrarySection(
        icon: Icons.favorite_rounded,
        label: 'Favourites',
        subtitle: '${favourites.length} songs',
        songs: favourites,
        color: const Color(0xFFE91E63),
      ),
      for (final pl in playlists)
        _LibrarySection(
          icon: Icons.queue_music_rounded,
          label: pl.title,
          subtitle: '${pl.songCount} songs',
          songs: pl.songs
              .map((e) => SongModel.fromMap(e))
              .toList(),
          color: const Color(0xFF5C6BC0),
        ),
    ];

    return RotaryScrollWrapper(
      controller: scrollController,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 24),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final section = sections[index];
          return _LibraryTile(
            section: section,
            onTap: () => _openSection(context, section),
          );
        },
      ),
    );
  }

  void _openSection(BuildContext context, _LibrarySection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistScreen(
          title: section.label,
          songs: section.songs,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class _LibrarySection {
  final IconData icon;
  final String label;
  final String subtitle;
  final List<SongModel> songs;
  final Color color;

  const _LibrarySection({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.songs,
    required this.color,
  });
}

// ---------------------------------------------------------------------------
// Tile widget
// ---------------------------------------------------------------------------
class _LibraryTile extends StatelessWidget {
  final _LibrarySection section;
  final VoidCallback onTap;

  const _LibraryTile({
    required this.section,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: section.color.withAlpha(40),
              ),
              child: Icon(section.icon, color: section.color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    section.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF555555), size: 18),
          ],
        ),
      ),
    );
  }
}
