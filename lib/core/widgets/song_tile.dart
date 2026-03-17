import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:gyawun/core/widgets/library_tile.dart';
import 'package:gyawun/core/widgets/tiles/tile_more_button.dart';
import 'package:gyawun/services/media_player.dart';
import 'package:gyawun/utils/bottom_modals.dart';

class SongTile extends StatelessWidget {
  const SongTile({required this.song, this.playlistId, super.key});

  final String? playlistId;
  final Map song;

  @override
  Widget build(BuildContext context) {
    final List thumbnails = song['thumbnails'] as List;
    final double height =
        (song['aspectRatio'] != null ? 50 / (song['aspectRatio'] as num) : 50)
            .toDouble();

    final String title = song['title'] as String? ?? '';
    final String artistSubtitle = song['subtitle'] as String? ??
        (song['artists'] as List?)?.map((e) => (e as Map)['name']).join(', ') ??
        '';
    final String semanticLabel =
        artistSubtitle.isNotEmpty ? '$title by $artistSubtitle' : title;

    return Semantics(
      label: semanticLabel,
      hint: 'Double tap to play',
      child: LibraryTile(
        onTap: () async {
          if (song['endpoint'] != null && song['videoId'] == null) {
            context.push('/browse', extra: {'endpoint': song['endpoint']});
          } else {
            await GetIt.I<MediaPlayer>().playSong(Map.from(song));
          }
        },
        onLongPress: () {
          if (song['videoId'] != null) {
            Modals.showSongBottomModal(context, song);
          }
        },
        title: Text(
          title,
          maxLines: 1,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: thumbnails
                .where((el) => (el as Map)['width'] >= 50)
                .toList()
                .first['url'] as String,
            height: height,
            width: 50,
            fit: BoxFit.cover,
          ),
        ),
        subtitle: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (song['explicit'] == true)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.explicit,
                  size: 18,
                  color: Colors.grey.withValues(alpha: 0.9),
                ),
              ),
            if (song['isVideo'] == true)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.videocam,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            Expanded(
              child: Text(
                artistSubtitle,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(context).colorScheme.onSurface.withAlpha(150),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: song['videoId'] == null
            ? null
            : TileMoreButton(song: song, itemTitle: title, filled: true),
      ),
    );
  }
}
