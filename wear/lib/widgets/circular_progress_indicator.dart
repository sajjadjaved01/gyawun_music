import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// WatchProgressArc
//
// CustomPainter that draws a circular arc around the screen edge, representing
// playback progress. Designed for round 384×384 – 480×480 Wear OS displays.
//
// Usage:
//   CustomPaint(
//     painter: WatchProgressArc(progress: 0.65, isAmbient: false),
//   )
// ---------------------------------------------------------------------------
class WatchProgressArc extends CustomPainter {
  /// Playback progress from 0.0 to 1.0.
  final double progress;

  /// Accent colour for the progress stroke. Ignored when [isAmbient] is true.
  final Color color;

  /// Track (background) colour.
  final Color trackColor;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// In ambient mode the arc is drawn in monochrome (dim white) with no
  /// anti-aliasing to conserve OLED power.
  final bool isAmbient;

  const WatchProgressArc({
    required this.progress,
    this.color = const Color(0xFF1DB954),
    this.trackColor = const Color(0xFF2A2A2A),
    this.strokeWidth = 6.0,
    this.isAmbient = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Inset by half the stroke width so the arc stays inside the clip.
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth / 2;

    // Arc starts at 12 o'clock (top) and sweeps clockwise.
    const startAngle = -math.pi / 2;
    const fullSweep = 2 * math.pi;
    final progressSweep = fullSweep * progress.clamp(0.0, 1.0);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = isAmbient
          ? const Color(0xFF444444)
          : trackColor
      ..isAntiAlias = !isAmbient;

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = isAmbient
          ? const Color(0xFFAAAAAA)
          : color
      ..isAntiAlias = !isAmbient;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track — full circle.
    canvas.drawArc(rect, startAngle, fullSweep, false, trackPaint);

    // Progress arc.
    if (progressSweep > 0) {
      canvas.drawArc(rect, startAngle, progressSweep, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(WatchProgressArc old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.isAmbient != isAmbient;
}

// ---------------------------------------------------------------------------
// Convenience widget wrapper
// ---------------------------------------------------------------------------
class PlaybackProgressArc extends StatelessWidget {
  final double progress;
  final bool isAmbient;
  final Widget? child;
  final Color color;
  final double strokeWidth;

  const PlaybackProgressArc({
    super.key,
    required this.progress,
    this.isAmbient = false,
    this.child,
    this.color = const Color(0xFF1DB954),
    this.strokeWidth = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WatchProgressArc(
        progress: progress,
        color: color,
        strokeWidth: strokeWidth,
        isAmbient: isAmbient,
      ),
      child: child,
    );
  }
}
