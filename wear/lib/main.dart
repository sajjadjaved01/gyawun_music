import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:wear_plus/wear_plus.dart';

import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'services/watch_media_player.dart';
import 'services/watch_sync_service.dart';

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait — Wear OS round faces are always square/round.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialise just_audio_background for media notifications / Bluetooth controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.jhelum.gyawun.wear.channel.audio',
    androidNotificationChannelName: 'Gyawun Wear Audio',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: false,
  );

  // Initialise Hive with three boxes:
  //   WATCH_SETTINGS  – user preferences (volume, loop mode, etc.)
  //   WATCH_DOWNLOADS – locally synced audio file metadata
  //   WATCH_LIBRARY   – playlists and favourites received from the phone
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox<dynamic>('WATCH_SETTINGS'),
    Hive.openBox<dynamic>('WATCH_DOWNLOADS'),
    Hive.openBox<dynamic>('WATCH_LIBRARY'),
  ]);

  // Register singletons before the widget tree is built.
  final mediaPlayer = WatchMediaPlayer();
  final syncService = WatchSyncService();

  GetIt.I.registerSingleton<WatchMediaPlayer>(mediaPlayer);
  GetIt.I.registerSingleton<WatchSyncService>(syncService);

  // Kick off Data Layer initialisation asynchronously so the app does not
  // block on Wearable API configuration (which can fail on non-paired devices).
  syncService.init().catchError(
    (Object e) => debugPrint('[main] syncService.init error: $e'),
  );

  runApp(
    // Expose WatchMediaPlayer as a ChangeNotifier to the whole tree.
    ChangeNotifierProvider<WatchMediaPlayer>.value(
      value: mediaPlayer,
      child: const GyawunWearApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Root application
// ---------------------------------------------------------------------------
class GyawunWearApp extends StatelessWidget {
  const GyawunWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gyawun Music',
      debugShowCheckedModeBanner: false,

      // Dark OLED theme — black backgrounds conserve power on Wear OS AMOLED.
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          secondary: Color(0xFF1DB954),
          surface: Color(0xFF121212),
        ),
        scaffoldBackgroundColor: Colors.black,
        visualDensity: VisualDensity.compact,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        fontFamily: 'Roboto',
      ),

      // AmbientMode wraps the root so every descendant can query the mode.
      home: AmbientMode(
        builder: (context, mode) => const _WearRootPage(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Root page — vertical PageView (standard Wear OS navigation pattern)
//
// Page order:
//   0  Search
//   1  Library
//   2  Now Playing  <-- default
//   3  Queue
//   4  Settings
// ---------------------------------------------------------------------------
class _WearRootPage extends StatefulWidget {
  const _WearRootPage();

  @override
  State<_WearRootPage> createState() => _WearRootPageState();
}

class _WearRootPageState extends State<_WearRootPage> {
  static const int _initialPage = 2; // Now Playing
  late final PageController _pageController =
      PageController(initialPage: _initialPage);

  int _currentPage = _initialPage;

  static const List<_NavPage> _pages = [
    _NavPage(icon: Icons.search_rounded, label: 'Search'),
    _NavPage(icon: Icons.library_music_rounded, label: 'Library'),
    _NavPage(icon: Icons.music_note_rounded, label: 'Now Playing'),
    _NavPage(icon: Icons.queue_music_rounded, label: 'Queue'),
    _NavPage(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main page content
          PageView(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (page) => setState(() => _currentPage = page),
            children: const [
              SearchScreen(),
              LibraryScreen(),
              NowPlayingScreen(),
              QueueScreen(),
              SettingsScreen(),
            ],
          ),

          // Page indicator dots on the right edge
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_pages.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    width: isActive ? 5 : 3,
                    height: isActive ? 5 : 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? const Color(0xFF1DB954)
                          : const Color(0xFF444444),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation page metadata
// ---------------------------------------------------------------------------
class _NavPage {
  final IconData icon;
  final String label;

  const _NavPage({required this.icon, required this.label});
}
