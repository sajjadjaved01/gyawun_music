import 'package:flutter/material.dart';
import 'package:wear_os_rotary_plugin/wear_os_rotary_plugin.dart';

// ---------------------------------------------------------------------------
// RotaryScrollWrapper
//
// Wraps any scrollable widget with WearOsScrollbar from wear_os_rotary_plugin,
// which handles Samsung bezel / Pixel Watch crown rotary input and displays
// a circular scrollbar overlay.
//
// Usage:
//   RotaryScrollWrapper(
//     child: (controller) => ListView.builder(
//       controller: controller,
//       ...
//     ),
//   )
// ---------------------------------------------------------------------------
class RotaryScrollWrapper extends StatelessWidget {
  final Widget Function(ScrollController controller) child;

  /// Whether to show the circular scrollbar indicator.
  final bool showScrollbar;

  const RotaryScrollWrapper({
    super.key,
    required this.child,
    this.showScrollbar = true,
  });

  @override
  Widget build(BuildContext context) {
    return WearOsScrollbar(
      autoHide: true,
      autoHideDuration: const Duration(seconds: 2),
      builder: (context, rotaryScrollController) =>
          child(rotaryScrollController),
    );
  }
}

// ---------------------------------------------------------------------------
// Convenience mixin for StatefulWidgets that need a ScrollController for
// non-list rotary usage (e.g. volume control on NowPlaying screen).
// ---------------------------------------------------------------------------
mixin RotaryScrollMixin<T extends StatefulWidget> on State<T> {
  late final ScrollController scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
