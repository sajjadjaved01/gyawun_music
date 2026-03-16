import 'package:hive_flutter/hive_flutter.dart';

enum SmartPlaylistType { mostPlayed, recentlyPlayed, leastPlayed }

extension SmartPlaylistTypeX on SmartPlaylistType {
  String get title {
    switch (this) {
      case SmartPlaylistType.mostPlayed:
        return 'Most Played';
      case SmartPlaylistType.recentlyPlayed:
        return 'Recently Played';
      case SmartPlaylistType.leastPlayed:
        return 'Least Played';
    }
  }

  String get subtitle {
    switch (this) {
      case SmartPlaylistType.mostPlayed:
        return 'Your top 50 tracks';
      case SmartPlaylistType.recentlyPlayed:
        return 'Last 50 songs you played';
      case SmartPlaylistType.leastPlayed:
        return 'Rediscover forgotten tracks';
    }
  }
}

/// Queries existing Hive boxes to compute smart playlists on demand.
/// No separate Hive box is created.
class SmartPlaylistService {
  static const int _limit = 50;

  List<Map<String, dynamic>> getSongs(SmartPlaylistType type) {
    final box = Hive.box('SONG_HISTORY');
    final all = box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    switch (type) {
      case SmartPlaylistType.mostPlayed:
        all.sort(
          (a, b) => ((b['plays'] as num?) ?? 0).compareTo(
            (a['plays'] as num?) ?? 0,
          ),
        );
        return all.take(_limit).toList();

      case SmartPlaylistType.recentlyPlayed:
        all.sort(
          (a, b) => ((b['updatedAt'] as num?) ?? 0).compareTo(
            (a['updatedAt'] as num?) ?? 0,
          ),
        );
        return all.take(_limit).toList();

      case SmartPlaylistType.leastPlayed:
        final once = all.where((s) => (s['plays'] as num?) == 1).toList();
        once.sort(
          (a, b) => ((a['updatedAt'] as num?) ?? 0).compareTo(
            (b['updatedAt'] as num?) ?? 0,
          ),
        );
        return once.take(_limit).toList();
    }
  }
}
