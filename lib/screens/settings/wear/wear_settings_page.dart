import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gyawun/core/widgets/expressive_app_bar.dart';
import 'package:gyawun/core/widgets/expressive_list_group.dart';
import 'package:gyawun/core/widgets/expressive_list_tile.dart';
import 'package:gyawun/core/widgets/expressive_switch_list_tile.dart';
import 'package:gyawun/screens/settings/widgets/color_icon.dart';
import 'package:gyawun/services/bottom_message.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'cubit/wear_settings_cubit.dart';

class WearSettingsPage extends StatelessWidget {
  const WearSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WearSettingsCubit(),
      child: BlocListener<WearSettingsCubit, WearSettingsState>(
        listenWhen: (_, state) => state.lastAction != null,
        listener: (context, state) {
          final action = state.lastAction;
          if (action == null) return;

          switch (action) {
            case WearSettingsAction.syncStarted:
              BottomMessage.showText(context, 'Syncing to watch...');
            case WearSettingsAction.syncCompleted:
              BottomMessage.showText(context, 'Watch sync complete.');
            case WearSettingsAction.syncFailed:
              BottomMessage.showText(
                context,
                'Sync failed. Is your watch connected?',
              );
          }

          context.read<WearSettingsCubit>().consumeAction();
        },
        child: const _WearSettingsView(),
      ),
    );
  }
}

class _WearSettingsView extends StatelessWidget {
  const _WearSettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            const ExpressiveAppBar(title: 'Wear OS', hasLeading: true),
          ];
        },
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: BlocBuilder<WearSettingsCubit, WearSettingsState>(
              builder: (context, state) {
                final cubit = context.read<WearSettingsCubit>();
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    // --------------------------------------------------------
                    // Watch status
                    // --------------------------------------------------------
                    ExpressiveListGroup(
                      title: 'Watch',
                      children: [
                        ExpressiveListTile(
                          leading: SettingsColorIcon(
                            icon: FluentIcons.smartwatch_24_filled,
                            color: const Color.fromARGB(155, 70, 141, 92),
                          ),
                          title: Text(
                            state.watchName ?? 'No watch connected',
                          ),
                          subtitle: Text(_connectionLabel(state.connectionStatus)),
                          trailing: _connectionChip(
                            context,
                            state.connectionStatus,
                          ),
                          onTap: cubit.refresh,
                        ),
                        ExpressiveListTile(
                          leading: SettingsColorIcon(
                            icon: FluentIcons.arrow_sync_24_filled,
                            color: const Color.fromARGB(155, 70, 120, 180),
                          ),
                          title: const Text('Last synced'),
                          subtitle: Text(_lastSyncLabel(state.lastSyncedAt)),
                          trailing: state.isSyncing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  FluentIcons.chevron_right_24_filled,
                                ),
                          onTap: state.isSyncing ? null : cubit.triggerSync,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // --------------------------------------------------------
                    // Sync content toggles
                    // --------------------------------------------------------
                    ExpressiveListGroup(
                      title: 'What to sync',
                      children: [
                        ExpressiveSwitchListTile(
                          leading: const SettingsColorIcon(
                            icon: FluentIcons.heart_24_filled,
                            color: Color.fromARGB(155, 183, 86, 118),
                          ),
                          title: const Text('Favourites'),
                          value: state.syncFavourites,
                          onChanged: cubit.toggleSyncFavourites,
                        ),
                        ExpressiveSwitchListTile(
                          leading: const SettingsColorIcon(
                            icon: FluentIcons.history_24_filled,
                            color: Color.fromARGB(155, 115, 84, 46),
                          ),
                          title: const Text('Playback history'),
                          value: state.syncHistory,
                          onChanged: cubit.toggleSyncHistory,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // --------------------------------------------------------
                    // Playlist sync toggles (loaded from Hive LIBRARY box)
                    // --------------------------------------------------------
                    _PlaylistSyncGroup(state: state, cubit: cubit),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _connectionLabel(WatchConnectionStatus status) {
    switch (status) {
      case WatchConnectionStatus.connected:
        return 'Connected and reachable';
      case WatchConnectionStatus.disconnected:
        return 'No watch found nearby';
      case WatchConnectionStatus.unknown:
        return 'Checking connection...';
    }
  }

  Widget _connectionChip(
    BuildContext context,
    WatchConnectionStatus status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case WatchConnectionStatus.connected:
        return Chip(
          label: const Text('Connected'),
          backgroundColor:
              colorScheme.primaryContainer.withValues(alpha: 0.6),
          labelStyle: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: 11,
          ),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      case WatchConnectionStatus.disconnected:
        return Chip(
          label: const Text('Offline'),
          backgroundColor:
              colorScheme.errorContainer.withValues(alpha: 0.6),
          labelStyle: TextStyle(
            color: colorScheme.onErrorContainer,
            fontSize: 11,
          ),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
      case WatchConnectionStatus.unknown:
        return const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }

  String _lastSyncLabel(int? lastSyncedAt) {
    if (lastSyncedAt == null) return 'Never synced';
    final dt = DateTime.fromMillisecondsSinceEpoch(lastSyncedAt);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Reads playlists from the Hive LIBRARY box and shows a toggle for each one.
class _PlaylistSyncGroup extends StatelessWidget {
  const _PlaylistSyncGroup({
    required this.state,
    required this.cubit,
  });

  final WearSettingsState state;
  final WearSettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('LIBRARY').listenable(),
      builder: (context, Box box, _) {
        final keys = box.keys.toList();
        if (keys.isEmpty) return const SizedBox.shrink();

        return ExpressiveListGroup(
          title: 'Playlists',
          children: [
            for (final key in keys)
              _playlistTile(context, key as String, box),
          ],
        );
      },
    );
  }

  Widget _playlistTile(BuildContext context, String key, Box box) {
    final raw = box.get(key);
    if (raw == null) return const SizedBox.shrink();

    final m = Map<String, dynamic>.from(raw as Map);
    final title = m['title'] as String? ?? key;
    final songCount = (m['songs'] as List?)?.length ?? 0;
    final isSynced = state.syncedPlaylistKeys.contains(key);

    return ExpressiveSwitchListTile(
      leading: SettingsColorIcon(
        icon: FluentIcons.music_note_2_24_filled,
        color: const Color.fromARGB(155, 130, 70, 180),
      ),
      title: Text(title),
      subtitle: Text('$songCount song${songCount == 1 ? '' : 's'}'),
      value: isSynced,
      onChanged: (enabled) =>
          cubit.togglePlaylistSync(key, enabled: enabled),
    );
  }
}
