/// Typed model for a user playlist stored in the Hive LIBRARY box.
class PlaylistModel {
  final String title;
  final bool isPredefined;
  final List<Map<String, dynamic>> songs;
  final int createdAt;
  final String? playlistId;
  final String? subtitle;
  final List<Map<String, dynamic>> thumbnails;
  final String? type;
  final Map<String, dynamic>? endpoint;

  const PlaylistModel({
    required this.title,
    required this.isPredefined,
    this.songs = const [],
    required this.createdAt,
    this.playlistId,
    this.subtitle,
    this.thumbnails = const [],
    this.type,
    this.endpoint,
  });

  int get songCount => songs.length;

  String? get thumbnailUrl =>
      thumbnails.isNotEmpty ? thumbnails.first['url'] as String? : null;

  factory PlaylistModel.fromMap(Map<dynamic, dynamic> map) {
    List<Map<String, dynamic>> castList(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    Map<String, dynamic>? castMap(dynamic value) {
      if (value == null) return null;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    return PlaylistModel(
      title: map['title'] as String? ?? '',
      isPredefined: map['isPredefined'] == true,
      songs: castList(map['songs']),
      createdAt: map['createdAt'] as int? ?? 0,
      playlistId: map['playlistId'] as String?,
      subtitle: map['subtitle'] as String?,
      thumbnails: castList(map['thumbnails']),
      type: map['type'] as String?,
      endpoint: castMap(map['endpoint']),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'title': title,
      'isPredefined': isPredefined,
      'songs': songs,
      'createdAt': createdAt,
    };
    if (playlistId != null) map['playlistId'] = playlistId;
    if (subtitle != null) map['subtitle'] = subtitle;
    if (thumbnails.isNotEmpty) map['thumbnails'] = thumbnails;
    if (type != null) map['type'] = type;
    if (endpoint != null) map['endpoint'] = endpoint;
    return map;
  }

  PlaylistModel copyWith({
    String? title,
    bool? isPredefined,
    List<Map<String, dynamic>>? songs,
    int? createdAt,
    String? playlistId,
    String? subtitle,
    List<Map<String, dynamic>>? thumbnails,
    String? type,
    Map<String, dynamic>? endpoint,
  }) {
    return PlaylistModel(
      title: title ?? this.title,
      isPredefined: isPredefined ?? this.isPredefined,
      songs: songs ?? this.songs,
      createdAt: createdAt ?? this.createdAt,
      playlistId: playlistId ?? this.playlistId,
      subtitle: subtitle ?? this.subtitle,
      thumbnails: thumbnails ?? this.thumbnails,
      type: type ?? this.type,
      endpoint: endpoint ?? this.endpoint,
    );
  }

  @override
  String toString() => 'PlaylistModel(title: $title, songs: ${songs.length})';
}
