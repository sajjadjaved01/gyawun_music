import 'package:flutter/material.dart';

/// A full-area centered empty-state with an icon and a message.
///
/// Usage:
/// ```dart
/// if (songs.isEmpty) return AppEmptyState(
///   icon: Icons.music_off_rounded,
///   message: 'No songs yet',
///   subtitle: 'Add songs to your library to see them here.',
/// );
/// ```
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    required this.message,
    this.subtitle,
    this.action,
  });

  /// Icon rendered above the message.
  final IconData icon;

  /// Primary message shown below the icon.
  final String message;

  /// Optional secondary line with additional context.
  final String? subtitle;

  /// Optional action widget (e.g. a button to create content).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: subtitle != null ? '$message. $subtitle' : message,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 64,
                color: colorScheme.onSurface.withAlpha(80),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withAlpha(180),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withAlpha(120),
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
