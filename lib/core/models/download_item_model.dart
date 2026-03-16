/// Typed model for a single song entry tracked by [DownloadManager].
class DownloadItemModel {
  final String videoId;
  final String title;
  final String? subtitle;
  final List<Map<String, dynamic>> artists;
  final Map<String, dynamic>? album;
  final List<Map<String, dynamic>> thumbnails;
  final String? type;
  final bool explicit;
  final double? aspectRatio;
  final String? description;

  /// One of: `QUEUED`, `DOWNLOADING`, `DOWNLOADED`, `FAILED`, `DELETED`.
  final String status;
  final String? path;
  final Map<String, dynamic> downloadPlaylists;

  const DownloadItemModel({
    required this.videoId,
    required this.title,
    this.subtitle,
    this.artists = const [],
    this.album,
    this.thumbnails = const [],
    this.type,
    this.explicit = false,
    this.aspectRatio,
    this.description,
    required this.status,
    this.path,
    this.downloadPlaylists = const {},
  });

  bool get isDownloaded => status == 'DOWNLOADED';
  bool get isDownloading => status == 'DOWNLOADING';
  bool get isQueued => status == 'QUEUED';
  bool get isFailed => status == 'FAILED';
  bool get isDeleted => status == 'DELETED';

  String get artistNames =>
      artists.map((a) => a['name'] as String? ?? '').join(', ');

  String? get thumbnailUrl {
    if (thumbnails.isEmpty) return null;
    final wide = thumbnails.where((t) => (t['width'] as num? ?? 0) >= 50);
    final chosen = wide.isNotEmpty ? wide.first : thumbnails.first;
    return chosen['url'] as String?;
  }

  factory DownloadItemModel.fromMap(Map<dynamic, dynamic> map) {
    List<Map<String, dynamic>> castList(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    Map<String, dynamic> castMapRequired(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return {};
    }

    Map<String, dynamic>? castMap(dynamic value) {
      if (value == null) return null;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    return DownloadItemModel(
      videoId: map['videoId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String?,
      artists: castList(map['artists']),
      album: castMap(map['album']),
      thumbnails: castList(map['thumbnails']),
      type: map['type'] as String?,
      explicit: map['explicit'] == true,
      aspectRatio: (map['aspectRatio'] as num?)?.toDouble(),
      description: map['description'] as String?,
      status: map['status'] as String? ?? 'QUEUED',
      path: map['path'] as String?,
      downloadPlaylists: castMapRequired(map['playlists']),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'videoId': videoId,
      'title': title,
      'status': status,
      'playlists': downloadPlaylists,
    };
    if (subtitle != null) map['subtitle'] = subtitle;
    if (artists.isNotEmpty) map['artists'] = artists;
    if (album != null) map['album'] = album;
    if (thumbnails.isNotEmpty) map['thumbnails'] = thumbnails;
    if (type != null) map['type'] = type;
    if (explicit) map['explicit'] = explicit;
    if (aspectRatio != null) map['aspectRatio'] = aspectRatio;
    if (description != null) map['description'] = description;
    if (path != null) map['path'] = path;
    return map;
  }

  DownloadItemModel copyWith({
    String? videoId,
    String? title,
    String? subtitle,
    List<Map<String, dynamic>>? artists,
    Map<String, dynamic>? album,
    List<Map<String, dynamic>>? thumbnails,
    String? type,
    bool? explicit,
    double? aspectRatio,
    String? description,
    String? status,
    String? path,
    Map<String, dynamic>? downloadPlaylists,
  }) {
    return DownloadItemModel(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      thumbnails: thumbnails ?? this.thumbnails,
      type: type ?? this.type,
      explicit: explicit ?? this.explicit,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      description: description ?? this.description,
      status: status ?? this.status,
      path: path ?? this.path,
      downloadPlaylists: downloadPlaylists ?? this.downloadPlaylists,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadItemModel &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId;

  @override
  int get hashCode => videoId.hashCode;

  @override
  String toString() =>
      'DownloadItemModel(videoId: $videoId, title: $title, status: $status)';
}
