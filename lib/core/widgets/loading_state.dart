import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

/// A full-area centered loading indicator that matches the app's M3 style.
///
/// Usage:
/// ```dart
/// if (isLoading) return const AppLoadingState();
/// ```
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    super.key,
    this.semanticLabel = 'Loading',
  });

  /// Label read by screen readers while content is loading.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: const Center(
        child: LoadingIndicatorM3E(),
      ),
    );
  }
}
