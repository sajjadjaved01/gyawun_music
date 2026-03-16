part of 'library_cubit.dart';

@immutable
sealed class LibraryState {
  const LibraryState();
}

class LibraryLoading extends LibraryState {
  const LibraryLoading();
}

class LibraryLoaded extends LibraryState {
  final Map playlists;
  final int favouritesCount;
  final int downloadsCount;
  final int historyCount;
  final int mostPlayedCount;
  final int recentlyPlayedCount;
  final int leastPlayedCount;

  const LibraryLoaded({
    required this.playlists,
    required this.favouritesCount,
    required this.downloadsCount,
    required this.historyCount,
    this.mostPlayedCount = 0,
    this.recentlyPlayedCount = 0,
    this.leastPlayedCount = 0,
  });
}

class LibraryError extends LibraryState {
  final String message;
  const LibraryError(this.message);
}
