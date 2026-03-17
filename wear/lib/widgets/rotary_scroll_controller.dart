import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

// ---------------------------------------------------------------------------
// RotaryScrollWrapper
//
// Listens to rotary events (Samsung bezel / Pixel Watch crown) via the
// wearable_rotary package and drives a [ScrollController] accordingly.
//
// Wrap any scrollable widget (ListView, SingleChildScrollView, etc.) with
// this widget to get physical crown/bezel scrolling for free:
//
//   RotaryScrollWrapper(
//     controller: myScrollController,
//     child: ListView.builder(
//       controller: myScrollController,
//       ...
//     ),
//   )
// ---------------------------------------------------------------------------
class RotaryScrollWrapper extends StatefulWidget {
  final ScrollController controller;
  final Widget child;

  /// How many logical pixels one rotary notch maps to.
  final double pixelsPerNotch;

  const RotaryScrollWrapper({
    super.key,
    required this.controller,
    required this.child,
    this.pixelsPerNotch = 40.0,
  });

  @override
  State<RotaryScrollWrapper> createState() => _RotaryScrollWrapperState();
}

class _RotaryScrollWrapperState extends State<RotaryScrollWrapper> {
  StreamSubscription<RotaryEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = rotaryEvents.listen(_onRotary);
  }

  void _onRotary(RotaryEvent event) {
    if (!widget.controller.hasClients) return;

    final current = widget.controller.offset;
    final max = widget.controller.position.maxScrollExtent;
    final min = widget.controller.position.minScrollExtent;

    // Positive magnitude = clockwise = scroll down; negative = scroll up.
    final delta = event.magnitude * widget.pixelsPerNotch;
    final target = (current + delta).clamp(min, max);

    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Convenience mixin for StatefulWidgets that manage their own ScrollController
// and want rotary support with minimal boilerplate.
//
// Usage:
//   class _MyScreenState extends State<MyScreen>
//       with RotaryScrollMixin {
//     @override
//     Widget build(BuildContext context) {
//       return RotaryScrollWrapper(
//         controller: scrollController,
//         child: ListView(controller: scrollController, ...),
//       );
//     }
//   }
// ---------------------------------------------------------------------------
mixin RotaryScrollMixin<T extends StatefulWidget> on State<T> {
  late final ScrollController scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
