import 'package:flutter/material.dart';

/// A full-area centered error display with an optional retry button.
///
/// Usage:
/// ```dart
/// if (hasError) return AppErrorState(
///   message: 'Could not load songs.',
///   onRetry: cubit.reload,
/// );
/// ```
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.message,
    this.onRetry,
    this.icon,
  });

  /// Human-readable description of the error. Falls back to a generic message.
  final String? message;

  /// Called when the user taps the retry button.
  /// When null the retry button is hidden.
  final VoidCallback? onRetry;

  /// Override the default error icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: message ?? 'An error occurred',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Icons.error_outline_rounded,
                size: 56,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
