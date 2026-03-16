import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun/core/widgets/expressive_app_bar.dart';
import 'package:gyawun/core/widgets/song_tile.dart';
import 'package:gyawun/services/media_player.dart';
import 'package:gyawun/themes/text_styles.dart';

import '../../../generated/l10n.dart';
import '../../../services/smart_playlist_service.dart';
import '../../../utils/adaptive_widgets/adaptive_widgets.dart';
import 'cubit/smart_playlist_cubit.dart';

class SmartPlaylistPage extends StatelessWidget {
  const SmartPlaylistPage({super.key, required this.type});

  final SmartPlaylistType type;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SmartPlaylistCubit(type)..load(),
      child: BlocBuilder<SmartPlaylistCubit, SmartPlaylistState>(
        builder: (context, state) {
          return switch (state) {
            SmartPlaylistLoading() => const Scaffold(
              body: Center(child: AdaptiveProgressRing()),
            ),
            SmartPlaylistError(:final message) => Scaffold(
              body: Center(child: Text(message)),
            ),
            SmartPlaylistLoaded(:final songs) => _SmartPlaylistView(
              type: type,
              songs: songs,
            ),
          };
        },
      ),
    );
  }
}

class _SmartPlaylistView extends StatelessWidget {
  const _SmartPlaylistView({required this.type, required this.songs});

  final SmartPlaylistType type;
  final List<Map<String, dynamic>> songs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            ExpressiveAppBar(
              hasLeading: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(context).copyWith(fontSize: 16),
                  ),
                  SizedBox(height: 2),
                  Text(
                    S.of(context).nSongs(songs.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle(
                      context,
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ];
        },
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    FilledButton.icon(
                      style: const ButtonStyle(
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                              topLeft: Radius.circular(24),
                              bottomLeft: Radius.circular(24),
                            ),
                          ),
                        ),
                      ),
                      onPressed: songs.isEmpty
                          ? null
                          : () => GetIt.I<MediaPlayer>().playAll(songs),
                      icon: const Icon(FluentIcons.play_24_filled),
                      label: const Text('Play it'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonalIcon(
                      style: const ButtonStyle(
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                              topRight: Radius.circular(24),
                              bottomRight: Radius.circular(24),
                            ),
                          ),
                        ),
                      ),
                      onPressed: songs.isEmpty
                          ? null
                          : () {
                              final shuffled = List<Map<String, dynamic>>.from(
                                songs,
                              );
                              shuffled.shuffle();
                              GetIt.I<MediaPlayer>().playAll(shuffled);
                            },
                      icon: const Icon(FluentIcons.arrow_shuffle_24_filled),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ),
            ),
            if (songs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No songs yet.\nStart listening to fill this playlist.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: SongTile(song: songs[index]),
                  ),
                  childCount: songs.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
    );
  }
}
