import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gyawun/themes/typography.dart';

/// Central theme configuration for Gyawun Music.
///
/// Both [light] and [dark] return a [ThemeData] that can be passed directly to
/// [MaterialApp] or composed further with `toM3EThemeData` (from the
/// m3e_collection package) as done in [main.dart].
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Shared constants
  // ---------------------------------------------------------------------------

  static const _pageTransitions = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
    },
  );

  static const _lightOverlayStyle = SystemUiOverlayStyle(
    statusBarBrightness: Brightness.light,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  );

  static const _darkOverlayStyle = SystemUiOverlayStyle(
    statusBarBrightness: Brightness.dark,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  );

  // ---------------------------------------------------------------------------
  // Light theme
  // ---------------------------------------------------------------------------

  static ThemeData light({Color? primary}) {
    final seedColor = primary ?? Colors.red;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData.light(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: appTextTheme(ThemeData.light().textTheme),
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: _lightOverlayStyle,
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }

  // ---------------------------------------------------------------------------
  // Dark theme
  // ---------------------------------------------------------------------------

  static ThemeData dark({Color? primary, bool isPureBlack = false}) {
    final seedColor = primary ?? Colors.deepPurpleAccent;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor:
          isPureBlack ? Colors.black : colorScheme.surface,
      textTheme: appTextTheme(ThemeData.dark().textTheme),
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        backgroundColor: isPureBlack ? Colors.black : null,
        surfaceTintColor: isPureBlack ? Colors.black : null,
        systemOverlayStyle: _darkOverlayStyle,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isPureBlack ? Colors.black : null,
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }
}
