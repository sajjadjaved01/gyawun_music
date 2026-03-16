import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Renders a fixed-size thumbnail for a song or playlist item.
///
/// Handles the circular vs rounded-square shape based on [isArtist],
/// respects the display pixel ratio for cache sizing, and gracefully
/// falls back to a music note icon when [url] is null.
class TileThumbnail extends StatelessWidget {
  const TileThumbnail({
    super.key,
    required this.url,
    this.size = 50.0,
    this.isArtist = false,
  });

  /// Remote image URL. When null a placeholder icon is shown.
  final String? url;

  /// Square side length in logical pixels (default 50).
  final double size;

  /// Use a fully circular clip for artist thumbnails.
  final bool isArtist;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final borderRadius =
        isArtist ? size / 2 : 8.0;

    if (url == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.music_note, size: size * 0.5),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: (size * pixelRatio).round(),
          memCacheHeight: (size * pixelRatio).round(),
          errorWidget: (_, __, ___) =>
              Icon(Icons.music_note, size: size * 0.5),
        ),
      ),
    );
  }
}
