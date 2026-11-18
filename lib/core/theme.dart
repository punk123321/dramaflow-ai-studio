import 'package:flutter/material.dart';

class DfColors {
  static const bg = Color(0xFF080A1C);
  static const bgTop = Color(0xFF17144A);
  static const surface = Color(0xFF12153A);
  static const raise = Color(0xFF1B1F52);
  static const ink = Color(0xFFF1F2FF);
  static const muted = Color(0xFF9AA0CC);
  static const line = Color(0xFF2B3073);
  static const accent = Color(0xFF8B5CFF);
  static const accentDeep = Color(0xFF5B3BE0);
  static const onAccent = Color(0xFFFFFFFF);
  static const ok = Color(0xFF3DDC84);
  static const warn = Color(0xFFFF9F43);
  static const danger = Color(0xFFFF8A80);
}

/// Gradients shared by the home screen and the other studio screens.
class DfGradients {
  /// Page background: deep indigo at the top fading into the base colour.
  static const page = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [DfColors.bgTop, DfColors.bg],
    stops: [0.0, 0.55],
  );

  /// Main call-to-action (buttons, hero).
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9A6BFF), DfColors.accentDeep],
  );

  /// A tile gradient built from one base colour (lighter top-left, deeper bottom-right).
  static LinearGradient tile(Color base) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(base, Colors.white, 0.12)!,
          Color.lerp(base, Colors.black, 0.38)!,
        ],
      );
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
      backgroundColor: const Color(0xFF0C0E2B),
      surfaceTintColor: Colors.transparent,
      height: 68,
      indicatorColor: DfColors.accent.withValues(alpha: 0.28),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          color: on ? DfColors.ink : DfColors.muted,
          fontFamilyFallback: burmeseFallback,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return IconThemeData(color: on ? DfColors.accent : DfColors.muted);
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: DfColors.accentDeep,
        foregroundColor: DfColors.onAccent,
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontFamilyFallback: burmeseFallback),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DfColors.ink,
        minimumSize: const Size(64, 46),
        side: const BorderSide(color: DfColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: DfColors.accentDeep,
      foregroundColor: DfColors.onAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: DfColors.raise,
      selectedColor: DfColors.accent.withValues(alpha: 0.35),
      side: const BorderSide(color: DfColors.line),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: DfColors.ink, fontFamilyFallback: burmeseFallback),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: DfColors.raise,
        selectedBackgroundColor: DfColors.accent.withValues(alpha: 0.4),
        foregroundColor: DfColors.muted,
        selectedForegroundColor: DfColors.ink,
        side: const BorderSide(color: DfColors.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: DfColors.raise,
      contentTextStyle: const TextStyle(color: DfColors.ink, fontFamilyFallback: burmeseFallback),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DfColors.raise,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: DfColors.line),
      ),
    ),
  );
}
