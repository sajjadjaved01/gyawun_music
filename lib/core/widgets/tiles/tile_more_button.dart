import 'package:flutter/material.dart';
import 'package:gyawun/utils/bottom_modals.dart';

/// A "more options" icon button used as a [ListTile] / [LibraryTile] trailing
/// widget for song and section tiles.
///
/// Shows the bottom modal if [videoId] is non-null, otherwise does nothing.
class TileMoreButton extends StatelessWidget {
  const TileMoreButton({
    super.key,
    required this.song,
    required this.itemTitle,
    this.filled = false,
  });

  /// The song map that will be passed to [Modals.showSongBottomModal].
  final Map song;

  /// Human-readable title used for the accessibility label.
  final String itemTitle;

  /// When true renders a filled-tonal icon button; otherwise a plain icon button.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final String? videoId = song['videoId'] as String?;

    return Semantics(
      button: true,
      label: 'More options for $itemTitle',
      child: filled
          ? IconButton.filledTonal(
              onPressed: videoId != null
                  ? () => Modals.showSongBottomModal(context, song)
                  : null,
              icon: const Icon(Icons.more_vert_rounded),
            )
          : IconButton(
              onPressed: videoId != null
                  ? () => Modals.showSongBottomModal(context, song)
                  : null,
              icon: const Icon(Icons.more_vert_rounded),
            ),
    );
  }
}
