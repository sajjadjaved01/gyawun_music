part of 'smart_playlist_cubit.dart';

@immutable
sealed class SmartPlaylistState {
  const SmartPlaylistState();
}

class SmartPlaylistLoading extends SmartPlaylistState {
  const SmartPlaylistLoading();
}

class SmartPlaylistLoaded extends SmartPlaylistState {
  final List<Map<String, dynamic>> songs;
  const SmartPlaylistLoaded(this.songs);
}

class SmartPlaylistError extends SmartPlaylistState {
  final String message;
  const SmartPlaylistError(this.message);
}
