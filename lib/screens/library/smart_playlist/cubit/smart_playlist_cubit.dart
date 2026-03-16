import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../services/smart_playlist_service.dart';

part 'smart_playlist_state.dart';

class SmartPlaylistCubit extends Cubit<SmartPlaylistState> {
  final SmartPlaylistType type;
  final SmartPlaylistService _service = SmartPlaylistService();

  late final Box _box;
  late final VoidCallback _listener;

  SmartPlaylistCubit(this.type) : super(const SmartPlaylistLoading()) {
    _box = Hive.box('SONG_HISTORY');

    _listener = () {
      if (!isClosed) _emitState();
    };

    _box.listenable().addListener(_listener);
  }

  void load() {
    _emitState();
  }

  void _emitState() {
    if (isClosed) return;
    try {
      final songs = _service.getSongs(type);
      emit(SmartPlaylistLoaded(songs));
    } catch (e) {
      if (!isClosed) emit(SmartPlaylistError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _box.listenable().removeListener(_listener);
    return super.close();
  }
}
