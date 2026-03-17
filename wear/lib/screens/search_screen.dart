import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun_shared/gyawun_shared.dart';
import 'package:provider/provider.dart';

import '../services/watch_media_player.dart';
import '../services/watch_sync_service.dart';
import '../widgets/rotary_scroll_controller.dart';

// ---------------------------------------------------------------------------
// SearchScreen
// Voice search via Wear OS speech recognizer. Results are fetched from the
// phone through WatchSyncService.MessageClient.
// ---------------------------------------------------------------------------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _speechChannel =
      MethodChannel('com.jhelum.gyawun/speech');

  WatchSyncService get _sync => GetIt.I<WatchSyncService>();

  List<SongModel> _results = [];
  bool _isListening = false;
  bool _isSearching = false;
  String _lastQuery = '';
  String? _errorMessage;

  StreamSubscription<List<SongModel>>? _resultsSub;

  @override
  void initState() {
    super.initState();
    _resultsSub = _sync.searchResultsStream.listen((results) {
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Voice input via Wear OS SpeechRecognizer platform channel
  // ---------------------------------------------------------------------------
  Future<void> _startVoiceSearch() async {
    setState(() {
      _isListening = true;
      _errorMessage = null;
    });

    try {
      // The MainActivity exposes a "startSpeechRecognizer" method that
      // launches the system speech recognizer dialog and returns the
      // recognised text string.
      final result = await _speechChannel
          .invokeMethod<String>('startSpeechRecognizer')
          .timeout(const Duration(seconds: 15));

      if (result != null && result.trim().isNotEmpty) {
        _lastQuery = result.trim();
        await _sendQuery(_lastQuery);
      }
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Speech recognition failed';
      });
    } on TimeoutException {
      setState(() {
        _errorMessage = 'Timed out';
      });
    } finally {
      if (mounted) setState(() => _isListening = false);
    }
  }

  Future<void> _sendQuery(String query) async {
    setState(() {
      _isSearching = true;
      _results = [];
    });
    await _sync.sendSearchQuery(query);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Voice button area at the top
        const SizedBox(height: 18),
        _VoiceButton(
          isListening: _isListening,
          isSearching: _isSearching,
          lastQuery: _lastQuery,
          onTap: (_isListening || _isSearching) ? null : _startVoiceSearch,
        ),
        const SizedBox(height: 6),

        // Error banner
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFCF6679),
                fontSize: 10,
              ),
            ),
          ),

        // Results list
        Expanded(
          child: _isSearching
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF1DB954),
                    strokeWidth: 2,
                  ),
                )
              : _results.isEmpty
                  ? _EmptyResults(hasQuery: _lastQuery.isNotEmpty)
                  : RotaryScrollWrapper(
                      child: (controller) => ListView.builder(
                        controller: controller,
                        itemCount: _results.length,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemBuilder: (context, index) {
                          final song = _results[index];
                          return _SearchResultTile(
                            song: song,
                            onTap: () => _playSong(context, song),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Future<void> _playSong(BuildContext context, SongModel song) async {
    final player = context.read<WatchMediaPlayer>();
    await player.playSong(song.toMap());
  }
}

// ---------------------------------------------------------------------------
// Voice button
// ---------------------------------------------------------------------------
class _VoiceButton extends StatelessWidget {
  final bool isListening;
  final bool isSearching;
  final String lastQuery;
  final VoidCallback? onTap;

  const _VoiceButton({
    required this.isListening,
    required this.isSearching,
    required this.lastQuery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isListening
        ? const Color(0xFFCF6679)
        : const Color(0xFF1DB954);

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(isListening ? 60 : 30),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(
              child: isListening
                  ? const Icon(Icons.mic, color: Color(0xFFCF6679), size: 26)
                  : isSearching
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Color(0xFF1DB954),
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.mic_none_rounded,
                          color: Color(0xFF1DB954), size: 26),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isListening
              ? 'Listening...'
              : isSearching
                  ? 'Searching...'
                  : lastQuery.isNotEmpty
                      ? lastQuery
                      : 'Tap to search',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty results state
// ---------------------------------------------------------------------------
class _EmptyResults extends StatelessWidget {
  final bool hasQuery;

  const _EmptyResults({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hasQuery ? 'No results found' : 'Search for music',
        style: const TextStyle(
          color: Color(0xFF555555),
          fontSize: 12,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search result tile
// ---------------------------------------------------------------------------
class _SearchResultTile extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const _SearchResultTile({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.music_note_rounded,
                color: Color(0xFF555555), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  if (song.artistNames.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      song.artistNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
