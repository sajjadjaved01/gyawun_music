/// Typed model for a song/track returned by the YT Music API or stored in
/// Hive boxes (SONG_HISTORY, FAVOURITES, DOWNLOADS).
///
/// Hive always persists plain [Map] values, so [SongModel.fromMap] and
/// [SongModel.toMap] act as the conversion boundary.
class SongModel {
  final String videoId;
  final String title;
  final String? subtitle;
  final List<Map<String, dynamic>> artists;
  final Map<String, dynamic>? album;
  final List<Map<String, dynamic>> thumbnails;
  final String? type;
  final bool explicit;
  final double? aspectRatio;
  final Map<String, dynamic>? endpoint;
  final String? playlistRadioId;
  final String? description;

  // Download-specific fields
  final String? status;
  final String? path;
  final Map<String, dynamic>? playlists;

  // History-specific fields
  final int? plays;
  final int? updatedAt;
  final int? createdAt;

  const SongModel({
    required this.videoId,
    required this.title,
    this.subtitle,
    this.artists = const [],
    this.album,
    this.thumbnails = const [],
    this.type,
    this.explicit = false,
    this.aspectRatio,
    this.endpoint,
    this.playlistRadioId,
    this.description,
    this.status,
    this.path,
    this.playlists,
    this.plays,
    this.updatedAt,
    this.createdAt,
  });

  String get artistNames =>
      artists.map((a) => a['name'] as String? ?? '').join(', ');

  String? get thumbnailUrl {
    if (thumbnails.isEmpty) return null;
    final wide = thumbnails.where((t) => (t['width'] as num? ?? 0) >= 50);
    final chosen = wide.isNotEmpty ? wide.first : thumbnails.first;
    return chosen['url'] as String?;
  }

  bool get isDownloaded => status == 'DOWNLOADED';

  factory SongModel.fromMap(Map<dynamic, dynamic> map) {
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

    return SongModel(
      videoId: map['videoId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String?,
      artists: castList(map['artists']),
      album: castMap(map['album']),
      thumbnails: castList(map['thumbnails']),
      type: map['type'] as String?,
      explicit: map['explicit'] == true,
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble(),
      endpoint: castMap(map['endpoint']),
      playlistRadioId: map['playlistRadioId'] as String?,
      description: map['description'] as String?,
      status: map['status'] as String?,
      path: map['path'] as String?,
      playlists: castMap(map['playlists']),
      plays: map['plays'] as int?,
      updatedAt: map['updatedAt'] as int?,
      createdAt: (map['CreatedAt'] ?? map['createdAt']) as int?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'videoId': videoId,
      'title': title,
    };
    if (subtitle != null) map['subtitle'] = subtitle;
    if (artists.isNotEmpty) map['artists'] = artists;
    if (album != null) map['album'] = album;
    if (thumbnails.isNotEmpty) map['thumbnails'] = thumbnails;
    if (type != null) map['type'] = type;
    if (explicit) map['explicit'] = explicit;
    if (aspectRatio != null) map['aspectRatio'] = aspectRatio;
    if (endpoint != null) map['endpoint'] = endpoint;
    if (playlistRadioId != null) map['playlistRadioId'] = playlistRadioId;
    if (description != null) map['description'] = description;
    if (status != null) map['status'] = status;
    if (path != null) map['path'] = path;
    if (playlists != null) map['playlists'] = playlists;
    if (plays != null) map['plays'] = plays;
    if (updatedAt != null) map['updatedAt'] = updatedAt;
    if (createdAt != null) map['CreatedAt'] = createdAt;
    return map;
  }

  SongModel copyWith({
    String? videoId,
    String? title,
    String? subtitle,
    List<Map<String, dynamic>>? artists,
    Map<String, dynamic>? album,
    List<Map<String, dynamic>>? thumbnails,
    String? type,
    bool? explicit,
    double? aspectRatio,
    Map<String, dynamic>? endpoint,
    String? playlistRadioId,
    String? description,
    String? status,
    String? path,
    Map<String, dynamic>? playlists,
    int? plays,
    int? updatedAt,
    int? createdAt,
  }) {
    return SongModel(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      thumbnails: thumbnails ?? this.thumbnails,
      type: type ?? this.type,
      explicit: explicit ?? this.explicit,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      endpoint: endpoint ?? this.endpoint,
      playlistRadioId: playlistRadioId ?? this.playlistRadioId,
      description: description ?? this.description,
      status: status ?? this.status,
      path: path ?? this.path,
      playlists: playlists ?? this.playlists,
      plays: plays ?? this.plays,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongModel &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId;

  @override
  int get hashCode => videoId.hashCode;

  @override
  String toString() => 'SongModel(videoId: $videoId, title: $title)';
}
