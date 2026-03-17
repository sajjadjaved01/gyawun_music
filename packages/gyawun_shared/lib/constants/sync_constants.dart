/// Constants for Wear OS ↔ Phone sync protocol.
abstract final class SyncConstants {
  // Message paths for Wearable Data Layer API
  static const String playbackCommand = '/playback/command';
  static const String playbackState = '/playback/state';
  static const String librarySync = '/library/sync';
  static const String libraryData = '/library/data';
  static const String downloadRequest = '/download/request';
  static const String downloadProgress = '/download/progress';
  static const String searchQuery = '/search/query';
  static const String searchResults = '/search/results';

  // Playback command values
  static const String cmdPlay = 'play';
  static const String cmdPause = 'pause';
  static const String cmdNext = 'next';
  static const String cmdPrev = 'prev';
  static const String cmdSeek = 'seek';

  // Data item paths
  static const String dataPlaybackState = '/data/playback_state';
  static const String dataLibrary = '/data/library';
  static const String dataDownloads = '/data/downloads';

  // Capability names
  static const String phoneCapability = 'gyawun_phone';
  static const String watchCapability = 'gyawun_watch';
}
