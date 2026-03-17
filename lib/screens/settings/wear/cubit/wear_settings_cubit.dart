import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_wear_os_connectivity/flutter_wear_os_connectivity.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'wear_settings_state.dart';

/// Hive SETTINGS keys used by wear sync preferences.
abstract final class _WearKeys {
  static const String syncFavourites = 'WEAR_SYNC_FAVOURITES';
  static const String syncHistory = 'WEAR_SYNC_HISTORY';
  static const String syncedPlaylists = 'WEAR_SYNCED_PLAYLISTS';
  static const String lastSyncedAt = 'WEAR_LAST_SYNCED_AT';
}

class WearSettingsCubit extends Cubit<WearSettingsState> {
  WearSettingsCubit() : super(WearSettingsState.initial()) {
    _load();
  }

  final Box _settings = Hive.box('SETTINGS');
  final WearOsConnectivity _wearOs = WearOsConnectivity();

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    // Load persisted preferences first so the UI shows something immediately.
    final syncedRaw = _settings.get(
      _WearKeys.syncedPlaylists,
      defaultValue: <String>[],
    );
    final syncedKeys = <String>{
      ...((syncedRaw as List?)?.whereType<String>() ?? []),
    };

    emit(
      state.copyWith(
        syncFavourites: _settings.get(
          _WearKeys.syncFavourites,
          defaultValue: true,
        ),
        syncHistory: _settings.get(
          _WearKeys.syncHistory,
          defaultValue: true,
        ),
        syncedPlaylistKeys: syncedKeys,
        lastSyncedAt: _settings.get(_WearKeys.lastSyncedAt) as int?,
      ),
    );

    await _refreshDeviceInfo();
  }

  /// Query the Wearable API for the currently paired watch.
  Future<void> _refreshDeviceInfo() async {
    try {
      await _wearOs.configureWearableAPI();

      final devices = await _wearOs.getConnectedDevices(
        capabilityName: SyncConstants.watchCapability,
      );

      if (devices.isEmpty) {
        emit(
          state.copyWith(
            connectionStatus: WatchConnectionStatus.disconnected,
            clearWatch: true,
          ),
        );
        return;
      }

      final watch = devices.first;
      emit(
        state.copyWith(
          connectionStatus: WatchConnectionStatus.connected,
          watchName: watch.name,
          watchNodeId: watch.id,
        ),
      );
    } catch (e) {
      debugPrint('[WearSettingsCubit] Failed to query device info: $e');
      emit(state.copyWith(connectionStatus: WatchConnectionStatus.unknown));
    }
  }

  // ---------------------------------------------------------------------------
  // Public actions
  // ---------------------------------------------------------------------------

  /// Refresh the connected watch info (called by pull-to-refresh or on resume).
  Future<void> refresh() => _refreshDeviceInfo();

  /// Toggle syncing of a user playlist identified by its Hive key.
  Future<void> togglePlaylistSync(String playlistKey, {required bool enabled}) async {
    final updated = Set<String>.from(state.syncedPlaylistKeys);
    if (enabled) {
      updated.add(playlistKey);
    } else {
      updated.remove(playlistKey);
    }
    await _settings.put(_WearKeys.syncedPlaylists, updated.toList());
    emit(state.copyWith(syncedPlaylistKeys: updated));
  }

  Future<void> toggleSyncFavourites(bool value) async {
    await _settings.put(_WearKeys.syncFavourites, value);
    emit(state.copyWith(syncFavourites: value));
  }

  Future<void> toggleSyncHistory(bool value) async {
    await _settings.put(_WearKeys.syncHistory, value);
    emit(state.copyWith(syncHistory: value));
  }

  /// Trigger a full library re-sync to the watch.
  Future<void> triggerSync() async {
    if (state.isSyncing) return;
    final nodeId = state.watchNodeId;
    if (nodeId == null) {
      emit(state.copyWith(lastAction: WearSettingsAction.syncFailed));
      return;
    }

    emit(
      state.copyWith(
        isSyncing: true,
        lastAction: WearSettingsAction.syncStarted,
      ),
    );

    try {
      // Request the WearSyncService to push library data by sending a
      // self-addressed library sync message.  The service handles the actual
      // Hive reads and DataClient push.
      await _wearOs.sendMessage(
        SyncConstants.librarySync,
        data: [],
        targetNodeId: nodeId,
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      await _settings.put(_WearKeys.lastSyncedAt, now);

      emit(
        state.copyWith(
          isSyncing: false,
          lastSyncedAt: now,
          lastAction: WearSettingsAction.syncCompleted,
        ),
      );
    } catch (e) {
      debugPrint('[WearSettingsCubit] Sync failed: $e');
      emit(
        state.copyWith(
          isSyncing: false,
          lastAction: WearSettingsAction.syncFailed,
        ),
      );
    }
  }

  /// Clear the one-shot action so the UI stops reacting to it.
  void consumeAction() {
    emit(state.copyWith(clearLastAction: true));
  }
}
