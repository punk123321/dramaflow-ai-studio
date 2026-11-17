import 'package:flutter/material.dart';

class DfColors {
  static const bg = Color(0xFF090B14);
  static const surface = Color(0xFF121627);
  static const raise = Color(0xFF1A1F35);
  static const ink = Color(0xFFECEEF8);
  static const muted = Color(0xFF8F96B3);
  static const line = Color(0xFF262C47);
  static const accent = Color(0xFF8B5CF6);
  static const secondary = Color(0xFF22D3EE);
  static const pink = Color(0xFFEC4899);
  static const onAccent = Color(0xFF12082A);
  static const ok = Color(0xFF3DDC84);
  static const warn = Color(0xFFFF9F43);
  static const danger = Color(0xFFFF8A80);
}

/// Used when the bundled Burmese font is not installed (see pubspec.yaml).
const List<String> burmeseFallback = [
  'Noto Sans Myanmar',
  'Padauk',
  'Myanmar Text',
];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DfColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: DfColors.accent,
    onPrimary: DfColors.onAccent,
    surface: DfColors.surface,
    onSurface: DfColors.ink,
    error: DfColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: DfColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: DfColors.ink,
      displayColor: DfColors.ink,
      fontFamilyFallback: burmeseFallback,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: DfColors.bg,
      foregroundColor: DfColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: DfColors.bg,
      indicatorColor: DfColors.accent.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontFamilyFallback: burmeseFallback),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DfColors.raise,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DfColors.line),
      ),
    ),
  );
}
