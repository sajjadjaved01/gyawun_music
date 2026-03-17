import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Shows a local video file in the player instead of album art.
/// Falls back to the provided [fallback] widget if the path is invalid or
/// the platform doesn't support the file.
class VideoArtwork extends StatefulWidget {
  const VideoArtwork({
    super.key,
    required this.path,
    required this.width,
    required this.fallback,
  });

  final String path;
  final double width;
  final Widget fallback;

  @override
  State<VideoArtwork> createState() => _VideoArtworkState();
}

class _VideoArtworkState extends State<VideoArtwork> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _initController(widget.path);
  }

  @override
  void didUpdateWidget(covariant VideoArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _disposeController();
      _initController(widget.path);
    }
  }

  Future<void> _initController(String path) async {
    if (!File(path).existsSync()) {
      if (mounted) setState(() => _error = true);
      return;
    }
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _controller = controller;
      setState(() {
        _initialized = true;
        _error = false;
      });
    } catch (_) {
      controller.dispose();
      if (mounted) setState(() => _error = true);
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initialized = false;
    _error = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error || !_initialized || _controller == null) {
      return widget.fallback;
    }

    return SizedBox(
      width: widget.width,
      height: widget.width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}
