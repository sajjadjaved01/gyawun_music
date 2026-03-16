import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:gyawun/core/widgets/expressive_app_bar.dart';
import 'package:gyawun/core/widgets/expressive_list_group.dart';
import 'package:gyawun/core/widgets/expressive_list_tile.dart';
import 'package:gyawun/core/widgets/expressive_switch_list_tile.dart';
import 'package:gyawun/screens/settings/widgets/color_icon.dart';
import 'package:gyawun/services/settings_manager.dart';

import '../../../generated/l10n.dart';
import 'cubit/player_settings_cubit.dart';

class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlayerSettingsCubit(),
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [ExpressiveAppBar(title: "Player", hasLeading: true)];
          },
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: BlocBuilder<PlayerSettingsCubit, PlayerSettingsState>(
                builder: (context, state) {
                  final s = state as PlayerSettingsLoaded;

                  return ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      ExpressiveListGroup(
                        children: [
                          ExpressiveListTile(
                            title: Text(S.of(context).Loudness_And_Equalizer),
                            leading: SettingsColorIcon(
                              icon: Icons.equalizer_rounded,
                            ),
                            trailing:
                                Icon(FluentIcons.chevron_right_24_filled),
                            onTap: () =>
                                context.go('/settings/player/equalizer'),
                          ),
                          ExpressiveSwitchListTile(
                            title: Text(S.of(context).Skip_Silence),
                            leading: SettingsColorIcon(
                              icon: FluentIcons.fast_forward_24_filled,
                            ),
                            value: s.skipSilence,
                            onChanged: (value) {
                              context
                                  .read<PlayerSettingsCubit>()
                                  .setSkipSilence(value);
                            },
                          ),
                          _CrossfadeTile(
                            currentValue: s.crossfadeDuration,
                            onChanged: (value) {
                              context
                                  .read<PlayerSettingsCubit>()
                                  .setCrossfadeDuration(value);
                            },
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrossfadeTile extends StatelessWidget {
  final int currentValue;
  final ValueChanged<int> onChanged;

  const _CrossfadeTile({
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = currentValue == 0 ? 'Off' : '${currentValue}s';

    return ExpressiveListTile(
      title: const Text('Crossfade'),
      subtitle: Text(label),
      leading: SettingsColorIcon(icon: Icons.swap_horiz_rounded),
      trailing: Icon(FluentIcons.chevron_right_24_filled),
      onTap: () => _showCrossfadePicker(context),
    );
  }

  void _showCrossfadePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CrossfadePickerSheet(
        currentValue: currentValue,
        onChanged: onChanged,
      ),
    );
  }
}

class _CrossfadePickerSheet extends StatelessWidget {
  final int currentValue;
  final ValueChanged<int> onChanged;

  const _CrossfadePickerSheet({
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Crossfade Duration',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Smoothly transition between tracks by fading out '
                'the current song and fading in the next.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ...SettingsManager.crossfadeDurationOptions.map((seconds) {
                final isSelected = currentValue == seconds;
                final label =
                    seconds == 0 ? 'Off (Gapless)' : '$seconds seconds';
                return _OptionTile(
                  label: label,
                  isSelected: isSelected,
                  onTap: () {
                    onChanged(seconds);
                    Navigator.of(context).pop();
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: colorScheme.primary)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
      onTap: onTap,
    );
  }
}
