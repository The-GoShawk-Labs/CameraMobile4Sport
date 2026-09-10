import 'package:flutter/material.dart';

class AppTheme {
  // Główne kolory tła i powierzchni
  static const Color background = Color(0xFF080B11);
  static const Color surface = Color(0xFF0F1420);
  static const Color surfaceCard = Color(0xFF161E2E);
  static const Color surfaceCardLight = Color(0xFF222C40);
  static const Color surfaceOverlay = Color(0xEB0C111A);
  
  // Neonowe akcenty transmisyjne
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color amberAccent = Color(0xFFFFAB00);
  static const Color greenLive = Color(0xFF00E676);
  static const Color redLive = Color(0xFFFF1744);
  static const Color purpleAccent = Color(0xFF7C4DFF);
  static const Color goldAccent = Color(0xFFFFD54F);

  // Kolory drużyn domyślne
  static const Color teamADefault = Color(0xFF00E5FF);
  static const Color teamBDefault = Color(0xFFFF9100);

  // Teksty
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF90A4AE);
  static const Color textMuted = Color(0xFF607D8B);

  // Gradienty
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B101A), Color(0xFF05070B)],
  );

  static const LinearGradient liveRedGradient = LinearGradient(
    colors: [Color(0xFFFF1744), Color(0xFFFF5252)],
  );

  static const LinearGradient cyanNeonGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
  );

  static const LinearGradient amberGoldGradient = LinearGradient(
    colors: [Color(0xFFFFAB00), Color(0xFFFFD54F)],
  );

  static const LinearGradient glassCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xEE161F2E), Color(0xEE0B1019)],
  );

  // Cienie i poświaty neonowe
  static List<BoxShadow> cyanGlow({double blur = 14, double opacity = 0.3}) => [
    BoxShadow(
      color: cyanAccent.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 1,
    ),
  ];

  static List<BoxShadow> amberGlow({double blur = 14, double opacity = 0.3}) => [
    BoxShadow(
      color: amberAccent.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 1,
    ),
  ];

  static List<BoxShadow> redGlow({double blur = 14, double opacity = 0.4}) => [
    BoxShadow(
      color: redLive.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 1,
    ),
  ];

  // Typografia sportowa
  static const TextStyle sportScoreLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1.0,
  );

  static const TextStyle broadcastHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.2,
    color: Colors.white,
  );

  static const TextStyle statusPillText = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.8,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: cyanAccent,
      colorScheme: const ColorScheme.dark(
        primary: cyanAccent,
        secondary: amberAccent,
        surface: surface,
        error: redLive,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyanAccent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surfaceCard,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFF222E42), width: 1.2),
        ),
      ),
    );
  }
}
