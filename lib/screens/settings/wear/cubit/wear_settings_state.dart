part of 'wear_settings_cubit.dart';

/// Represents the current connection status of a paired Wear OS device.
enum WatchConnectionStatus { unknown, connected, disconnected }

/// One-shot actions emitted by [WearSettingsCubit] that the UI should react
/// to exactly once (e.g. show a snack-bar).
enum WearSettingsAction {
  syncStarted,
  syncCompleted,
  syncFailed,
  installSent,
  installFailed,
}

class WearSettingsState {
  final WatchConnectionStatus connectionStatus;

  /// Display name reported by the paired watch, or null if no watch is found.
  final String? watchName;

  /// Opaque device-id used to address Wearable API calls.
  final String? watchNodeId;

  /// Whether the sync operation is currently in progress.
  final bool isSyncing;

  /// Whether the Gyawun Wear app is installed on the watch.
  final bool? isWearAppInstalled;

  /// Unix-millisecond timestamp of the last successful sync, or null.
  final int? lastSyncedAt;

  /// Keys of LIBRARY playlists that the user has opted in to sync.
  final Set<String> syncedPlaylistKeys;

  /// Whether favourites list should be synced to the watch.
  final bool syncFavourites;

  /// Whether playback history should be synced to the watch.
  final bool syncHistory;

  /// One-shot action for the UI listener (null when no pending action).
  final WearSettingsAction? lastAction;

  const WearSettingsState({
    this.connectionStatus = WatchConnectionStatus.unknown,
    this.watchName,
    this.watchNodeId,
    this.isSyncing = false,
    this.isWearAppInstalled,
    this.lastSyncedAt,
    this.syncedPlaylistKeys = const {},
    this.syncFavourites = true,
    this.syncHistory = true,
    this.lastAction,
  });

  factory WearSettingsState.initial() => const WearSettingsState();

  WearSettingsState copyWith({
    WatchConnectionStatus? connectionStatus,
    String? watchName,
    String? watchNodeId,
    bool clearWatch = false,
    bool? isSyncing,
    bool? isWearAppInstalled,
    int? lastSyncedAt,
    Set<String>? syncedPlaylistKeys,
    bool? syncFavourites,
    bool? syncHistory,
    WearSettingsAction? lastAction,
    bool clearLastAction = false,
  }) {
    return WearSettingsState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      watchName: clearWatch ? null : (watchName ?? this.watchName),
      watchNodeId: clearWatch ? null : (watchNodeId ?? this.watchNodeId),
      isSyncing: isSyncing ?? this.isSyncing,
      isWearAppInstalled: isWearAppInstalled ?? this.isWearAppInstalled,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncedPlaylistKeys: syncedPlaylistKeys ?? this.syncedPlaylistKeys,
      syncFavourites: syncFavourites ?? this.syncFavourites,
      syncHistory: syncHistory ?? this.syncHistory,
      lastAction: clearLastAction ? null : (lastAction ?? this.lastAction),
    );
  }
}
