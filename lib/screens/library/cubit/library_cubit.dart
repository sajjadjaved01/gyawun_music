import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun/services/favourites_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../services/library.dart';

part 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  final LibraryService libraryService;

  late final Box _libraryBox;
  late final FavouritesManager _favourites;
  late final Box _downloadsBox;
  late final Box _historyBox;

  late final VoidCallback _listener;

  LibraryCubit(this.libraryService) : super(const LibraryLoading()) {
    _libraryBox = Hive.box('LIBRARY');
    _favourites = GetIt.I<FavouritesManager>();
    _downloadsBox = Hive.box('DOWNLOADS');
    _historyBox = Hive.box('SONG_HISTORY');

    _listener = _emitCurrentState;

    _libraryBox.listenable().addListener(_listener);
    _favourites.listenable.addListener(_listener);
    _downloadsBox.listenable().addListener(_listener);
    _historyBox.listenable().addListener(_listener);
  }

  void loadLibrary() {
    _emitCurrentState();
  }

  void _emitCurrentState() {
    try {
      final downloadedCount = _downloadsBox.values.length;

      emit(
        LibraryLoaded(
          playlists: libraryService.playlists,
          favourites: _favourites.playlist,
          downloadsCount: downloadedCount,
          historyCount: _historyBox.length,
        ),
      );
    } catch (e) {
      emit(LibraryError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _libraryBox.listenable().removeListener(_listener);
    _favourites.listenable.removeListener(_listener);
    _downloadsBox.listenable().removeListener(_listener);
    _historyBox.listenable().removeListener(_listener);
    return super.close();
  }
}
