import 'package:flutter/material.dart';

const studioBg = Color(0xFF121418);
const studioPanel = Color(0xFF1A1F27);
const studioPanel2 = Color(0xFF232A34);
const studioLine = Color(0xFF313844);
const studioText = Color(0xFFE7ECF2);
const studioMuted = Color(0xFF93A0B0);
const studioAccent = Color(0xFF3DDCB4);
const studioAmber = Color(0xFFE2B15A);
const studioDanger = Color(0xFFE16D6D);

ThemeData studioTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: studioBg,
    colorScheme: const ColorScheme.dark(
      surface: studioPanel,
      primary: studioAccent,
      secondary: studioAmber,
      error: studioDanger,
    ),
    dividerColor: studioLine,
    fontFamily: 'sans-serif',
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: studioPanel,
      foregroundColor: studioText,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: studioPanel,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Color(0xFF12161C),
      border: OutlineInputBorder(borderSide: BorderSide(color: studioLine)),
      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: studioPanel,
      selectedIconTheme: IconThemeData(color: studioAccent),
      indicatorColor: Color(0x333DDCB4),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

Color categoryColor(String category) {
  return switch (category) {
    'events' => studioAmber,
    'motors' => const Color(0xFF4CC2E0),
    'sensors' => studioAccent,
    'control' => const Color(0xFFB48CFF),
    'variables' => const Color(0xFFE28A4A),
    'myblocks' => const Color(0xFFE58AB8),
    'hub' => const Color(0xFF7AA2FF),
    _ => const Color(0xFFD0D4DC),
  };
}
