import 'package:flutter/material.dart';

/// NeverWin visual system: blue-cyan gradients, dark premium surfaces,
/// Liquid-Glass style frosted panels (see widgets/glass.dart).
class NeverWinTheme {
  static const Color deepBlue = Color(0xFF0A2540);
  static const Color oceanBlue = Color(0xFF144E8C);
  static const Color skyBlue = Color(0xFF29B6F6);
  static const Color iceCyan = Color(0xFF7DE3FF);
  static const Color inkBlack = Color(0xFF0B1220);
  static const Color panelDark = Color(0xFF101B30);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0B3C6E), Color(0xFF1283C9), Color(0xFF3ED3F2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF0B1220), Color(0xFF13263F)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD76A), Color(0xFFFF9D3D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData build({bool dark = true}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: skyBlue,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: skyBlue,
      surface: dark ? panelDark : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? inkBlack : const Color(0xFFF2F7FC),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF16263F) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Shared animation durations — fast, light, non-intrusive.
class NeverWinMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration banner = Duration(milliseconds: 350);
}
