import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../services/media_player.dart';

/// Wraps the artwork area and adds:
///   • Vertical drag down → dismiss player (like YouTube)
///   • Double-tap     → seek ±10 s (left 40 % = back, right 40 % = forward)
///   • Single tap     → forwarded to [onTap] (toggle lyrics)
///
/// Indicators fade out automatically after [_overlayLingerMs] milliseconds.
class GestureOverlay extends StatefulWidget {
  const GestureOverlay({
    super.key,
    required this.child,
    required this.onTap,
    required this.onSwipeDown,
    required this.width,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onSwipeDown;
  final double width;

  @override
  State<GestureOverlay> createState() => _GestureOverlayState();
}

class _GestureOverlayState extends State<GestureOverlay>
    with TickerProviderStateMixin {
  // ── constants ────────────────────────────────────────────────────────────
  static const int _overlayLingerMs = 1200; // how long the indicator stays
  static const Duration _fadeDuration = Duration(milliseconds: 200);
  static const int _seekSeconds = 10;
  static const double _swipeDownThreshold = 100.0; // pixels to trigger dismiss

  // ── skip overlay ─────────────────────────────────────────────────────────
  late final AnimationController _skipFadeCtrl;
  late final Animation<double> _skipFadeAnim;
  Timer? _skipHideTimer;
  bool _skipForward = true; // which side was tapped last
  int _pendingSeekSeconds = 0; // stacked seek total for label

  // ── swipe down to dismiss ──────────────────────────────────────────────
  double _dragDownAccum = 0;

  @override
  void initState() {
    super.initState();

    _skipFadeCtrl = AnimationController(
      vsync: this,
      duration: _fadeDuration,
    );
    _skipFadeAnim =
        CurvedAnimation(parent: _skipFadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _skipHideTimer?.cancel();
    _skipFadeCtrl.dispose();
    super.dispose();
  }

  // ── swipe down helpers ─────────────────────────────────────────────────

  void _onVerticalDragStart(DragStartDetails _) {
    _dragDownAccum = 0;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    _dragDownAccum += details.delta.dy;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // Dismiss if dragged down enough or with sufficient velocity
    if (_dragDownAccum > _swipeDownThreshold ||
        (details.velocity.pixelsPerSecond.dy > 300)) {
      widget.onSwipeDown();
    }
    _dragDownAccum = 0;
  }

  // ── skip helpers ──────────────────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details) {
    final double tapX = details.localPosition.dx;
    final double artWidth = widget.width;
    final bool isLeft = tapX < artWidth * 0.4;
    final bool isRight = tapX > artWidth * 0.6;

    if (!isLeft && !isRight) return; // centre tap — ignore

    final MediaPlayer mp = GetIt.I<MediaPlayer>();
    final Duration current = mp.player.position;
    final Duration total = mp.player.duration ?? Duration.zero;

    if (isLeft) {
      final Duration target =
          current - const Duration(seconds: _seekSeconds);
      mp.player.seek(target < Duration.zero ? Duration.zero : target);
      _pendingSeekSeconds =
          (_skipForward || _skipHideTimer == null || !_skipFadeCtrl.isAnimating)
              ? _seekSeconds
              : _pendingSeekSeconds + _seekSeconds;
      _skipForward = false;
    } else {
      final Duration target =
          current + const Duration(seconds: _seekSeconds);
      mp.player.seek(target > total ? total : target);
      _pendingSeekSeconds =
          (!_skipForward || _skipHideTimer == null || !_skipFadeCtrl.isAnimating)
              ? _seekSeconds
              : _pendingSeekSeconds + _seekSeconds;
      _skipForward = true;
    }

    setState(() {});
    _showSkipIndicator();
  }

  void _showSkipIndicator() {
    _skipFadeCtrl.forward();
    _skipHideTimer?.cancel();
    _skipHideTimer = Timer(Duration(milliseconds: _overlayLingerMs), () {
      if (mounted) {
        _skipFadeCtrl.reverse().then((_) {
          if (mounted) setState(() => _pendingSeekSeconds = 0);
        });
      }
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: _onDoubleTapDown,
      // Absorb the double-tap so onTap is not also fired on double-tap.
      onDoubleTap: () {},
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          _SkipIndicator(
            animation: _skipFadeAnim,
            forward: _skipForward,
            seconds: _pendingSeekSeconds,
            width: widget.width,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skip indicator — icon + label, left or right
// ─────────────────────────────────────────────────────────────────────────────

class _SkipIndicator extends StatelessWidget {
  const _SkipIndicator({
    required this.animation,
    required this.forward,
    required this.seconds,
    required this.width,
  });

  final Animation<double> animation;
  final bool forward;
  final int seconds;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (seconds == 0) return const SizedBox.shrink();

    return Positioned.fill(
      child: FadeTransition(
        opacity: animation,
        child: Align(
          alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: forward ? 0 : 12,
              right: forward ? 12 : 0,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    forward
                        ? Icons.forward_10_rounded
                        : Icons.replay_10_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${forward ? '+' : '-'}${seconds}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
