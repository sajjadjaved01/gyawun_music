import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../services/wear_bridge.dart';

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
  final WearBridge _bridge = WearBridge.instance;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
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

  Future<void> _refreshDeviceInfo() async {
    try {
      // Check if Gyawun Wear app is installed
      final bool wearAppInstalled = await _bridge.isWearAppInstalled();

      // Find watches with the Gyawun Wear app capability
      final capableNodes =
          await _bridge.findCapableNodes(SyncConstants.watchCapability);

      if (capableNodes.isEmpty) {
        // No watch with our app — check if any watch is connected at all
        final allNodes = await _bridge.getConnectedNodes();
        final hasWatch = allNodes.isNotEmpty;
        final watchName = hasWatch ? allNodes.first['name'] : null;

        emit(
          state.copyWith(
            connectionStatus: hasWatch
                ? WatchConnectionStatus.connected
                : WatchConnectionStatus.disconnected,
            watchName: watchName,
            isWearAppInstalled: wearAppInstalled,
            clearWatch: !hasWatch,
          ),
        );
        return;
      }

      final watch = capableNodes.first;
      emit(
        state.copyWith(
          connectionStatus: WatchConnectionStatus.connected,
          watchName: watch['name'],
          watchNodeId: watch['id'],
          isWearAppInstalled: wearAppInstalled,
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

  Future<void> refresh() => _refreshDeviceInfo();

  Future<void> togglePlaylistSync(
    String playlistKey, {
    required bool enabled,
  }) async {
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
      await _bridge.sendMessage(
        SyncConstants.librarySync,
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

  Future<void> installOnWatch() async {
    try {
      final result = await _bridge.openPlayStoreOnWatch();
      if (result) {
        emit(state.copyWith(lastAction: WearSettingsAction.installSent));
        return;
      }
    } catch (_) {
      // Play Store approach failed
    }

    try {
      final opened = await _bridge.openWearOsCompanion();
      if (opened) {
        emit(state.copyWith(lastAction: WearSettingsAction.installSent));
      } else {
        emit(state.copyWith(lastAction: WearSettingsAction.installFailed));
      }
    } catch (_) {
      emit(state.copyWith(lastAction: WearSettingsAction.installFailed));
    }
  }

  void consumeAction() {
    emit(state.copyWith(clearLastAction: true));
  }
}
