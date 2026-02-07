import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun/services/favourites_manager.dart';

part 'favourites_state.dart';

class FavouritesCubit extends Cubit<FavouritesState> {
  late final FavouritesManager _favourites;
  late final VoidCallback _listener;

  FavouritesCubit() : super(const FavouritesLoading()) {
    _favourites = GetIt.I<FavouritesManager>();

    _listener = () {
      if (!isClosed) {
        _emitState();
      }
    };

    _favourites.listenable.addListener(_listener);
  }

  void load() {
    _emitState();
  }

  void _emitState() {
    if (isClosed) return;

    try {
      emit(FavouritesLoaded(_favourites.playlist));
    } catch (e) {
      if (!isClosed) {
        emit(FavouritesError(e.toString()));
      }
    }
  }

  Future<void> remove(dynamic key) async {
    await _favourites.remove(key);
  }

  @override
  Future<void> close() {
    _favourites.listenable.removeListener(_listener);
    return super.close();
  }
}
